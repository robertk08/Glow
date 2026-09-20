import Observation
import SwiftData
import SwiftUI

@Observable @MainActor
final class ShowLibrary {
	private(set) var shows: [Show] = []
	private(set) var activeID = ""
	private(set) var container: ModelContainer
	private(set) var isLoaded = false
	private var isDemo = false
	
	private let store = NodeStore()
	private let decoder = JSONDecoder()
	
	private var endpoint: NodeEndpoint?
	private var client: Int?
	private var baseline: [String: Data] = [:]
	private var saves: Task<Void, Never>?
	private var loading: Task<Void, Never>?
	private var pending: Task<Void, Never>?
	private var isApplying = false
	private var missedSave = false
	
	private static let nothing = Show(name: "")
	
	init() {
		container = Self.empty()
		decoder.dateDecodingStrategy = .iso8601
		
		saves = Task { [weak self] in
			for await _ in NotificationCenter.default.notifications(named: ModelContext.didSave) {
				self?.changed()
			}
		}
	}
	
	var active: Show {
		shows.first { $0.id == activeID } ?? Self.nothing
	}
	
	func reach(_ state: LinkState, endpoint: NodeEndpoint, client: Int?) {
		self.endpoint = endpoint
		self.client = client
		
		guard state.isConnected else {
			guard !isDemo else { return }
			unload()
			return
		}
		
		if isDemo {
			isDemo = false
			unload()
		}
		
		startLoading()
	}
	
	func startDemo() {
		guard !isDemo else { return }
		guard let url = Bundle.main.url(forResource: "Demo", withExtension: "json") else { return }
		guard let data = try? Data(contentsOf: url), let file = try? decoder.decode(ShowFile.self, from: data), file.isReadable else { return }
		
		isDemo = true
		let show = Show(name: file.name)
		shows = [show]
		activeID = show.id
		
		Task {
			await fill(with: file.show)
			isLoaded = true
		}
	}
	
	func settle(_ phase: ScenePhase) {
		guard phase != .active, isLoaded, !isDemo else { return }
		pending?.cancel()
		pending = nil
		
		Task {
			await synchronise()
		}
	}
	
	func receive(_ notice: Wire.Notice?) {
		guard let notice, !isDemo, isLoaded else { return }
		
		Task {
			await accept(notice)
		}
	}
	
	func activate(_ show: Show) {
		guard show.id != activeID else { return }
		activeID = show.id
		
		Task {
			await commit { list in
				list.active = show.id
			}
			
			guard await open(show) else {
				unload()
				startLoading()
				return
			}
		}
	}
	
	func create(name: String) {
		let show = Show(name: Self.unusedName(name, among: shows))
		shows.append(show)
		activeID = show.id
		container = Self.empty()
		baseline = [:]
		
		Task {
			await commit { list in
				list.shows.append(show)
				list.active = show.id
			}
		}
	}
	
	func duplicate(_ show: Show) {
		Task {
			guard let endpoint else { return }
			
			var found: ShowContents?
			if show.id == activeID {
				found = contents()
			} else {
				found = await store.show(show.id, at: endpoint)
			}
			
			guard let copy = found else { return }
			await adopt(copy, named: show.name)
		}
	}
	
	func rename(_ show: Show, to name: String) {
		guard let index = shows.firstIndex(where: { $0.id == show.id }) else { return }
		shows[index].name = name
		
		Task {
			await commit { list in
				guard let found = list.shows.firstIndex(where: { $0.id == show.id }) else { return }
				list.shows[found].name = name
			}
		}
	}
	
	func delete(_ show: Show) {
		guard shows.count > 1 else { return }
		let wasActive = show.id == activeID
		shows.removeAll { $0.id == show.id }
		if wasActive, let next = shows.first { activeID = next.id }
		
		Task {
			await commit { list in
				list.shows.removeAll { $0.id == show.id }
				guard list.active == show.id else { return }
				list.active = list.shows.first?.id ?? ""
			}
			
			if let endpoint {
				_ = await store.deleteShow(show.id, at: endpoint, client: client)
			}
			
			guard wasActive, let next = shows.first(where: { $0.id == activeID }) else { return }
			
			guard await open(next) else {
				unload()
				startLoading()
				return
			}
		}
	}
	
	func contents() -> ShowContents {
		let context = container.mainContext
		let fixtures = (try? context.fetch(FetchDescriptor<Fixture>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
		let groups = (try? context.fetch(FetchDescriptor<FixtureGroup>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
		let made = (try? context.fetch(FetchDescriptor<StoredFixtureType>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
		let looks = (try? context.fetch(FetchDescriptor<Look>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
		
		var show = ShowContents()
		
		for group in groups {
			show.groups.append(ShowContents.Group(identifier: group.identifier, name: group.name, sortIndex: group.sortIndex, symbol: group.symbolOverride, tint: group.tintName))
		}
		
		for fixture in fixtures {
			let identifiers = fixture.belongsTo.map(\.identifier)
			show.lights.append(ShowContents.Light(identifier: fixture.identifier, typeID: fixture.typeID, name: fixture.name, address: fixture.address, sortIndex: fixture.sortIndex, symbol: fixture.symbolOverride, groups: identifiers, invertsPan: fixture.invertsPan, invertsTilt: fixture.invertsTilt))
		}
		
		for stored in made {
			show.made.append(stored.definition)
		}
		
		for look in looks {
			show.scenes.append(ShowContents.Scene(identifier: look.identifier, name: look.name, sortIndex: look.sortIndex, levels: look.levels))
		}
		
		return show
	}
	
	func exportable() -> ShowFile {
		ShowFile(name: active.name, show: contents())
	}
	
	func shareable() -> URL? {
		let pretty = JSONEncoder()
		pretty.outputFormatting = [.prettyPrinted, .sortedKeys]
		pretty.dateEncodingStrategy = .iso8601
		guard let data = try? pretty.encode(exportable()) else { return nil }
		
		let folder = URL.temporaryDirectory.appending(path: "Shared", directoryHint: .isDirectory)
		try? FileManager.default.removeItem(at: folder)
		try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		
		let url = folder.appending(path: "\(active.name).json")
		try? data.write(to: url)
		return url
	}
	
	func adopt(contentsOf url: URL) {
		guard url.startAccessingSecurityScopedResource() else { return }
		defer { url.stopAccessingSecurityScopedResource() }
		guard let data = try? Data(contentsOf: url), let file = try? decoder.decode(ShowFile.self, from: data), file.isReadable else { return }
		
		Task {
			await adopt(file.show, named: file.name)
		}
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
	
	private func load() async -> Bool {
		guard let endpoint else { return false }
		
		switch await store.shows(at: endpoint) {
		case .unreachable:
			return false
			
		case .blank:
			let first = Show(name: "Show 1")
			shows = [first]
			activeID = first.id
			container = Self.empty()
			baseline = [:]
			
			guard await commit({ list in
				list.shows = [first]
				list.active = first.id
			}) else {
				shows = []
				activeID = ""
				return false
			}
			
			isLoaded = true
			return true
			
		case let .list(list):
			guard let show = list.activeShow else { return false }
			shows = list.shows
			activeID = show.id
			return await open(show)
		}
	}
	
	private func startLoading() {
		guard !isLoaded, loading == nil else { return }
		
		loading = Task {
			while !Task.isCancelled, !isLoaded {
				if await load() { break }
				try? await Task.sleep(for: .seconds(2))
			}
			
			loading = nil
		}
	}
	
	private func open(_ show: Show) async -> Bool {
		guard let endpoint, let incoming = await store.show(show.id, at: endpoint) else { return false }
		await fill(with: incoming)
		isLoaded = true
		return true
	}
	
	private func adopt(_ contents: ShowContents, named name: String) async {
		guard let endpoint else { return }
		
		let show = Show(name: Self.unusedName(name, among: shows))
		shows.append(show)
		activeID = show.id
		
		for (key, data) in await Self.snapshot(of: contents) {
			guard let folder = Self.folder(key), let identifier = Self.identifier(key) else { continue }
			_ = await store.put(data, folder: folder, id: identifier, in: show.id, at: endpoint, client: client)
		}
		
		await commit { list in
			list.shows.append(show)
			list.active = show.id
		}
		
		_ = await open(show)
	}
	
	private func accept(_ notice: Wire.Notice) async {
		guard let endpoint else { return }
		
		guard let name = notice.folder, let identifier = notice.id, let show = notice.show else {
			guard case let .list(list) = await store.shows(at: endpoint) else { return }
			shows = list.shows
			guard list.active != activeID, let opening = list.activeShow else { return }
			activeID = opening.id
			
			guard await open(opening) else {
				unload()
				startLoading()
				return
			}
			return
		}
		
		guard show == activeID, let folder = NodeStore.Folder(rawValue: name) else { return }
		
		var data: Data?
		if !notice.isDelete {
			data = await store.object(folder, id: identifier, in: show, at: endpoint)
			guard data != nil else { return }
		}
		
		guard show == activeID else { return }
		
		isApplying = true
		apply(folder, data: data, identifier: identifier)
		baseline = await Self.snapshot(of: contents())
		isApplying = false
		catchUp()
	}
	
	private func catchUp() {
		guard missedSave else { return }
		missedSave = false
		changed()
	}
	
	private func apply(_ folder: NodeStore.Folder, data: Data?, identifier: String) {
		let context = container.mainContext
		
		switch folder {
		case .lights:
			let found = ((try? context.fetch(FetchDescriptor<Fixture>())) ?? []).first { $0.identifier == identifier }
			guard let data, let entry = try? decoder.decode(ShowContents.Light.self, from: data), let address = DMXAddress(entry.address) else {
				if let found { context.delete(found) }
				break
			}
			
			let fixture = found ?? Fixture(typeID: entry.typeID, name: entry.name, address: address, sortIndex: entry.sortIndex)
			fixture.identifier = entry.identifier
			fixture.typeID = entry.typeID
			fixture.address = entry.address
			fixture.name = entry.name
			fixture.sortIndex = entry.sortIndex
			fixture.symbolOverride = entry.symbol
			fixture.invertsPan = entry.invertsPan
			fixture.invertsTilt = entry.invertsTilt
			if found == nil { context.insert(fixture) }
			
			for group in (try? context.fetch(FetchDescriptor<FixtureGroup>())) ?? [] {
				fixture.belong(to: group, entry.groups.contains(group.identifier))
			}
		case .groups:
			let found = ((try? context.fetch(FetchDescriptor<FixtureGroup>())) ?? []).first { $0.identifier == identifier }
			guard let data, let entry = try? decoder.decode(ShowContents.Group.self, from: data) else {
				if let found { context.delete(found) }
				break
			}
			
			let group = found ?? FixtureGroup(name: entry.name, sortIndex: entry.sortIndex)
			group.identifier = entry.identifier
			group.name = entry.name
			group.sortIndex = entry.sortIndex
			group.symbolOverride = entry.symbol
			group.tintName = entry.tint
			if found == nil { context.insert(group) }
		case .made:
			let found = ((try? context.fetch(FetchDescriptor<StoredFixtureType>())) ?? []).first { $0.identifier == identifier }
			guard let data, let entry = try? decoder.decode(FixtureType.self, from: data) else {
				if let found { context.delete(found) }
				break
			}
			
			if let found {
				found.definition = entry
			} else {
				context.insert(StoredFixtureType(entry))
			}
		case .scenes:
			let found = ((try? context.fetch(FetchDescriptor<Look>())) ?? []).first { $0.identifier == identifier }
			guard let data, let entry = try? decoder.decode(ShowContents.Scene.self, from: data) else {
				if let found { context.delete(found) }
				break
			}
			
			let look = found ?? Look(name: entry.name, sortIndex: entry.sortIndex, levels: entry.levels)
			look.identifier = entry.identifier
			look.name = entry.name
			look.sortIndex = entry.sortIndex
			look.levels = entry.levels
			if found == nil { context.insert(look) }
		}
		
		try? context.save()
	}
	
	private func unload() {
		loading?.cancel()
		loading = nil
		guard isLoaded else { return }
		pending?.cancel()
		isLoaded = false
		shows = []
		activeID = ""
		baseline = [:]
		container = Self.empty()
	}
	
	private func fill(with incoming: ShowContents) async {
		isApplying = true
		
		let fresh = Self.empty()
		let context = fresh.mainContext
		var groups: [String: FixtureGroup] = [:]
		
		for entry in incoming.groups {
			let group = FixtureGroup(name: entry.name, sortIndex: entry.sortIndex)
			group.identifier = entry.identifier
			group.symbolOverride = entry.symbol
			group.tintName = entry.tint
			context.insert(group)
			groups[entry.identifier] = group
		}
		
		for entry in incoming.lights {
			guard let address = DMXAddress(entry.address) else { continue }
			let fixture = Fixture(typeID: entry.typeID, name: entry.name, address: address, sortIndex: entry.sortIndex)
			fixture.identifier = entry.identifier
			fixture.symbolOverride = entry.symbol
			fixture.invertsPan = entry.invertsPan
			fixture.invertsTilt = entry.invertsTilt
			context.insert(fixture)
			
			for identifier in entry.groups {
				guard let group = groups[identifier] else { continue }
				fixture.belong(to: group, true)
			}
		}
		
		for entry in incoming.made {
			context.insert(StoredFixtureType(entry))
		}
		
		for entry in incoming.scenes {
			let look = Look(name: entry.name, sortIndex: entry.sortIndex, levels: entry.levels)
			look.identifier = entry.identifier
			context.insert(look)
		}
		
		try? context.save()
		container = fresh
		baseline = await Self.snapshot(of: contents())
		isApplying = false
		catchUp()
	}
	
	@discardableResult private func commit(_ change: (inout ShowList) -> Void) async -> Bool {
		guard let endpoint, !isDemo else { return false }
		
		var list = ShowList(active: "", shows: [])
		
		switch await store.shows(at: endpoint) {
		case let .list(latest): list = latest
		case .blank: break
		case .unreachable: return false
		}
		
		change(&list)
		shows = list.shows
		activeID = list.active
		return await store.save(list, at: endpoint, client: client)
	}
	
	private func changed() {
		guard isLoaded, !isDemo else { return }
		
		guard !isApplying else {
			missedSave = true
			return
		}
		
		pending?.cancel()
		
		pending = Task {
			try? await Task.sleep(for: .milliseconds(300))
			guard !Task.isCancelled else { return }
			await synchronise()
		}
	}
	
	private func synchronise() async {
		guard let endpoint, isLoaded else { return }
		
		let showID = activeID
		let current = await Self.snapshot(of: contents())
		var written = baseline
		
		for (key, data) in current where baseline[key] != data {
			guard showID == activeID else { return }
			guard let folder = Self.folder(key), let identifier = Self.identifier(key) else { continue }
			guard await store.put(data, folder: folder, id: identifier, in: showID, at: endpoint, client: client) else { continue }
			written[key] = data
		}
		
		for key in baseline.keys where current[key] == nil {
			guard showID == activeID else { return }
			guard let folder = Self.folder(key), let identifier = Self.identifier(key) else { continue }
			guard await store.delete(folder, id: identifier, in: showID, at: endpoint, client: client) else { continue }
			written.removeValue(forKey: key)
		}
		
		guard showID == activeID else { return }
		baseline = written
	}
	
	nonisolated static func snapshot(of contents: ShowContents) async -> [String: Data] {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys]
		encoder.dateEncodingStrategy = .iso8601
		var out: [String: Data] = [:]
		
		for light in contents.lights {
			guard let data = try? encoder.encode(light) else { continue }
			out["\(NodeStore.Folder.lights.rawValue)/\(light.identifier)"] = data
		}
		
		for group in contents.groups {
			guard let data = try? encoder.encode(group) else { continue }
			out["\(NodeStore.Folder.groups.rawValue)/\(group.identifier)"] = data
		}
		
		for made in contents.made {
			guard let data = try? encoder.encode(made) else { continue }
			out["\(NodeStore.Folder.made.rawValue)/\(made.id)"] = data
		}
		
		for scene in contents.scenes {
			guard let data = try? encoder.encode(scene) else { continue }
			out["\(NodeStore.Folder.scenes.rawValue)/\(scene.identifier)"] = data
		}
		
		return out
	}
	
	private static func folder(_ key: String) -> NodeStore.Folder? {
		guard let slash = key.firstIndex(of: "/") else { return nil }
		return NodeStore.Folder(rawValue: String(key[key.startIndex..<slash]))
	}
	
	private static func identifier(_ key: String) -> String? {
		guard let slash = key.firstIndex(of: "/") else { return nil }
		return String(key[key.index(after: slash)...])
	}
	
	private static func empty() -> ModelContainer {
		let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
		let container = try! ModelContainer(for: Fixture.self, FixtureGroup.self, StoredFixtureType.self, Look.self, configurations: configuration)
		container.mainContext.undoManager = UndoManager()
		container.mainContext.autosaveEnabled = true
		return container
	}
}
