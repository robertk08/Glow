import Observation
import SwiftData
import SwiftUI

@Observable @MainActor
final class ShowLibrary {
	private(set) var shows: [Show]
	private(set) var activeID: String
	private(set) var container: ModelContainer
	
	private static let activeKey = "show.active"
	private static let suffixes = ["", "-wal", "-shm"]
	
	private static var folder: URL {
		URL.applicationSupportDirectory.appending(path: "Shows", directoryHint: .isDirectory)
	}
	
	private static var manifest: URL {
		folder.appending(path: "shows.json")
	}
	
	private static func store(_ id: String, _ suffix: String = "") -> URL {
		folder.appending(path: "\(id).store" + suffix)
	}
	
	init() {
		try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
		
		var loaded = Self.load()
		
		if loaded.isEmpty {
			loaded = [Show(name: "Show 1")]
			Self.save(loaded)
		}
		
		shows = loaded
		
		let stored = UserDefaults.standard.string(forKey: Self.activeKey)
		let opening: String
		if let stored, loaded.contains(where: { $0.id == stored }) {
			opening = stored
		} else {
			opening = loaded[0].id
		}
		
		activeID = opening
		container = Self.open(opening)
	}
	
	var active: Show {
		shows.first { $0.id == activeID } ?? shows[0]
	}
	
	func activate(_ show: Show) {
		guard show.id != activeID else { return }
		try? container.mainContext.save()
		activeID = show.id
		UserDefaults.standard.set(show.id, forKey: Self.activeKey)
		container = Self.open(show.id)
	}
	
	func create(name: String) {
		let show = Show(name: name)
		shows.append(show)
		Self.save(shows)
		activate(show)
	}
	
	func duplicate(_ show: Show) {
		var file = contents(of: show)
		file.name = Self.unusedName(show.name, among: shows)
		adopt(file)
	}
	
	func shareable(_ show: Show) -> URL? {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		encoder.dateEncodingStrategy = .iso8601
		guard let data = try? encoder.encode(contents(of: show)) else { return nil }
		
		let folder = URL.temporaryDirectory.appending(path: "Shared", directoryHint: .isDirectory)
		try? FileManager.default.removeItem(at: folder)
		try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		
		let url = folder.appending(path: "\(show.name).json")
		try? data.write(to: url)
		return url
	}
	
	static func unusedName(_ base: String, among shows: [Show]) -> String {
		let taken = Set(shows.map(\.name))
		guard taken.contains(base) else { return base }
		var index = 2
		
		while taken.contains("\(base) \(index)") {
			index += 1
		}
		
		return "\(base) \(index)"
	}
	
	func rename(_ show: Show, to name: String) {
		guard let index = shows.firstIndex(where: { $0.id == show.id }) else { return }
		shows[index].name = name
		Self.save(shows)
	}
	
	func delete(_ show: Show) {
		guard shows.count > 1 else { return }
		shows.removeAll { $0.id == show.id }
		Self.save(shows)
		
		for suffix in Self.suffixes {
			try? FileManager.default.removeItem(at: Self.store(show.id, suffix))
		}
		
		guard show.id == activeID, let next = shows.first else { return }
		activate(next)
	}
	
	func contents(of show: Show) -> ShowFile {
		let context: ModelContext
		if show.id == activeID {
			context = container.mainContext
		} else {
			context = ModelContext(Self.open(show.id))
		}
		
		let fixtures = (try? context.fetch(FetchDescriptor<Fixture>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
		let groups = (try? context.fetch(FetchDescriptor<FixtureGroup>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
		let profiles = (try? context.fetch(FetchDescriptor<CustomProfile>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
		let looks = (try? context.fetch(FetchDescriptor<Look>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
		
		var file = ShowFile(name: show.name, lights: [], groups: [], profiles: [], scenes: [])
		
		for group in groups {
			file.groups.append(ShowGroup(name: group.name, sortIndex: group.sortIndex, symbol: group.symbolOverride, tint: group.tintName))
		}
		
		for fixture in fixtures {
			file.lights.append(ShowLight(identifier: fixture.identifier, profileID: fixture.profileID, name: fixture.name, address: fixture.address, sortIndex: fixture.sortIndex, symbol: fixture.symbolOverride, group: fixture.group?.name, invertsPan: fixture.invertsPan, invertsTilt: fixture.invertsTilt))
		}
		
		for profile in profiles {
			file.profiles.append(ShowProfile(identifier: profile.identifier, name: profile.name, symbol: profile.symbol, channels: profile.channelList, isSubtractive: profile.isSubtractive))
		}
		
		for look in looks {
			file.scenes.append(ShowScene(name: look.name, sortIndex: look.sortIndex, levels: look.levels))
		}
		
		return file
	}
	
	func adopt(contentsOf url: URL) {
		guard url.startAccessingSecurityScopedResource() else { return }
		defer { url.stopAccessingSecurityScopedResource() }
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		guard let data = try? Data(contentsOf: url), let file = try? decoder.decode(ShowFile.self, from: data) else { return }
		guard file.version ?? "" <= ShowFile.current else { return }
		adopt(file)
	}
	
	func adopt(_ file: ShowFile) {
		let show = Show(name: Self.unusedName(file.name, among: shows))
		shows.append(show)
		Self.save(shows)
		
		let context = ModelContext(Self.open(show.id))
		var groups: [String: FixtureGroup] = [:]
		
		for entry in file.groups {
			let group = FixtureGroup(name: entry.name, sortIndex: entry.sortIndex)
			group.symbolOverride = entry.symbol
			group.tintName = entry.tint
			context.insert(group)
			groups[entry.name] = group
		}
		
		for entry in file.lights {
			guard let address = DMXAddress(entry.address) else { continue }
			let fixture = Fixture(profileID: entry.profileID, name: entry.name, address: address, sortIndex: entry.sortIndex)
			fixture.identifier = entry.identifier
			fixture.symbolOverride = entry.symbol
			fixture.invertsPan = entry.invertsPan ?? false
			fixture.invertsTilt = entry.invertsTilt ?? false
			context.insert(fixture)
			
			if let name = entry.group {
				fixture.group = groups[name]
			}
		}
		
		for entry in file.profiles {
			let profile = CustomProfile(name: entry.name, symbol: entry.symbol, channels: entry.channels, isSubtractive: entry.isSubtractive ?? false)
			profile.identifier = entry.identifier
			context.insert(profile)
		}
		
		for entry in file.scenes {
			let look = Look(name: entry.name, sortIndex: entry.sortIndex, levels: [:])
			look.levels = entry.levels
			context.insert(look)
		}
		
		try? context.save()
		activate(show)
	}
	
	private static func open(_ id: String) -> ModelContainer {
		let configuration = ModelConfiguration(url: store(id))
		let container = (try? ModelContainer(for: Fixture.self, FixtureGroup.self, CustomProfile.self, Look.self, configurations: configuration)) ?? scratch()
		container.mainContext.undoManager = UndoManager()
		return container
	}
	
	private static func scratch() -> ModelContainer {
		let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
		return try! ModelContainer(for: Fixture.self, FixtureGroup.self, CustomProfile.self, Look.self, configurations: configuration)
	}
	
	private static func load() -> [Show] {
		guard let data = try? Data(contentsOf: manifest) else { return [] }
		return (try? JSONDecoder().decode([Show].self, from: data)) ?? []
	}
	
	private static func save(_ shows: [Show]) {
		guard let data = try? JSONEncoder().encode(shows) else { return }
		try? data.write(to: manifest, options: .atomic)
	}
}
