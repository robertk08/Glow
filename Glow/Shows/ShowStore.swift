import Foundation
import SwiftData

final class ShowStore {
	let container: ModelContainer
	
	init() {
		let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
		container = try! ModelContainer(for: Fixture.self, FixtureGroup.self, StoredFixtureType.self, Look.self, Cue.self, configurations: configuration)
		container.mainContext.undoManager = UndoManager()
		container.mainContext.autosaveEnabled = true
	}
	
	func contents(_ folders: Set<NodeStore.Folder>, only identifier: String?, types: FixtureLibrary?) -> ShowContents {
		let context = container.mainContext
		var show = ShowContents()
		var fixtures: [Fixture] = []
		
		if !folders.isDisjoint(with: [.lights, .made]) { fixtures = (try? context.fetch(FetchDescriptor<Fixture>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? [] }
		if folders.contains(.lights) { show.lights = fixtures.map(\.entry) }
		if folders.contains(.groups) { show.groups = ((try? context.fetch(FetchDescriptor<FixtureGroup>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []).map(\.entry) }
		
		if folders.contains(.scenes) {
			var looks = FetchDescriptor<Look>(sortBy: [SortDescriptor(\.sortIndex)])
			if let identifier { looks.predicate = #Predicate { $0.identifier == identifier } }
			show.scenes = ((try? context.fetch(looks)) ?? []).map(\.entry)
		}
		
		if folders.contains(.cues) {
			var cues = FetchDescriptor<Cue>(sortBy: [SortDescriptor(\.sortIndex)])
			if let identifier { cues.predicate = #Predicate { $0.identifier == identifier } }
			show.cues = ((try? context.fetch(cues)) ?? []).map(\.entry)
		}
		
		if folders.contains(.made) {
			show.made = ((try? context.fetch(FetchDescriptor<StoredFixtureType>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []).map(\.definition)
			
			for fixture in fixtures where !show.made.contains(where: { $0.id == fixture.typeID }) {
				guard let definition = types?.type(fixture.typeID) else { continue }
				show.made.append(definition)
			}
		}
		
		guard let identifier else { return show }
		show.lights.removeAll { $0.identifier != identifier }
		show.groups.removeAll { $0.identifier != identifier }
		show.made.removeAll { $0.id != identifier }
		return show
	}
	
	func prune(keeping show: ShowContents) {
		let context = container.mainContext
		let lights = show.lights.map(\.identifier)
		let groups = show.groups.map(\.identifier)
		let made = show.made.map(\.id)
		let scenes = show.scenes.map(\.identifier)
		let cues = show.cues.map(\.identifier)
		context.undoManager?.disableUndoRegistration()
		defer { context.undoManager?.enableUndoRegistration() }
		
		discard(#Predicate<Fixture> { !lights.contains($0.identifier) })
		discard(#Predicate<FixtureGroup> { !groups.contains($0.identifier) })
		discard(#Predicate<StoredFixtureType> { !made.contains($0.identifier) })
		discard(#Predicate<Look> { !scenes.contains($0.identifier) })
		discard(#Predicate<Cue> { !cues.contains($0.identifier) })
		try? context.save()
	}
	
	func remove(_ folder: NodeStore.Folder, identifier: String) {
		let context = container.mainContext
		context.undoManager?.disableUndoRegistration()
		defer { context.undoManager?.enableUndoRegistration() }
		
		switch folder {
		case .lights: discard(#Predicate<Fixture> { $0.identifier == identifier })
		case .groups: discard(#Predicate<FixtureGroup> { $0.identifier == identifier })
		case .made: discard(#Predicate<StoredFixtureType> { $0.identifier == identifier })
		case .scenes: discard(#Predicate<Look> { $0.identifier == identifier })
		case .cues: discard(#Predicate<Cue> { $0.identifier == identifier })
		}
		
		try? context.save()
	}
	
	private func discard<Model: PersistentModel>(_ predicate: Predicate<Model>) {
		let context = container.mainContext
		
		for model in (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? [] {
			context.delete(model)
		}
	}
	
	func clear() {
		prune(keeping: ShowContents())
		container.mainContext.undoManager?.removeAllActions()
	}
	
	nonisolated static func changes(in note: Notification) -> (folders: Set<NodeStore.Folder>, touched: Set<PersistentIdentifier>?) {
		guard let info = note.userInfo else { return (ShowLibrary.everything, nil) }
		
		var found: Set<NodeStore.Folder> = []
		var touched: Set<PersistentIdentifier> = []
		var sawKey = false
		
		for key in [ModelContext.NotificationKey.insertedIdentifiers, .updatedIdentifiers, .deletedIdentifiers] {
			guard let ids = info[key.rawValue] as? [PersistentIdentifier] ?? info[key] as? [PersistentIdentifier] else { continue }
			sawKey = true
			
			for id in ids {
				switch id.entityName {
				case "Fixture": found.formUnion([.lights, .made])
				case "FixtureGroup": found.insert(.groups)
				case "StoredFixtureType": found.insert(.made)
				case "Look": found.insert(.scenes)
				case "Cue": found.insert(.cues)
				default: break
				}
				
				if key != .deletedIdentifiers, ["Look", "Cue"].contains(id.entityName) { touched.insert(id) }
			}
		}
		
		return sawKey ? (found, touched) : (ShowLibrary.everything, nil)
	}
}
