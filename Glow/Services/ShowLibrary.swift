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
			let first = Show(name: "Show 1")
			Self.adoptExistingStore(into: first.id)
			loaded = [first]
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
	
	func rename(_ show: Show, to name: String) {
		guard let index = shows.firstIndex(where: { $0.id == show.id }) else { return }
		shows[index].name = name
		Self.save(shows)
	}
	
	func delete(_ show: Show) {
		shows.removeAll { $0.id == show.id }
		Self.save(shows)
		
		for suffix in Self.suffixes {
			try? FileManager.default.removeItem(at: Self.store(show.id, suffix))
		}
		
		guard show.id == activeID, let next = shows.first else { return }
		activeID = next.id
		UserDefaults.standard.set(next.id, forKey: Self.activeKey)
		container = Self.open(next.id)
	}
	
	private static func open(_ id: String) -> ModelContainer {
		let configuration = ModelConfiguration(url: store(id))
		return try! ModelContainer(for: Fixture.self, FixtureGroup.self, CustomProfile.self, Look.self, configurations: configuration)
	}
	
	private static func adoptExistingStore(into id: String) {
		let manager = FileManager.default
		let existing = URL.applicationSupportDirectory.appending(path: "default.store")
		guard manager.fileExists(atPath: existing.path(percentEncoded: false)) else { return }
		
		for suffix in suffixes {
			let from = URL.applicationSupportDirectory.appending(path: "default.store" + suffix)
			try? manager.moveItem(at: from, to: store(id, suffix))
		}
	}
	
	private static func load() -> [Show] {
		guard let data = try? Data(contentsOf: manifest) else { return [] }
		return (try? JSONDecoder().decode([Show].self, from: data)) ?? []
	}
	
	private static func save(_ shows: [Show]) {
		guard let data = try? JSONEncoder().encode(shows) else { return }
		try? data.write(to: manifest)
	}
}
