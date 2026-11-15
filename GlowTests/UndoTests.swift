import Foundation
import SwiftData
import Testing

@testable import Glow

@MainActor
struct UndoTests {
	@Test(arguments: [UInt64(1), 2, 3])
	func undoNeverCrashesWhileOtherDevicesChangeAndDeleteWhatItWouldRestore(seed: UInt64) async throws {
		var state = seed &* 0x9E3779B97F4A7C15
		
		func roll(_ count: Int) -> Int {
			state = state &* 6364136223846793005 &+ 1442695040888963407
			return Int((state >> 33) % UInt64(max(count, 1)))
		}
		
		let console = Console()
		let library = FixtureLibrary()
		let shows = ShowLibrary()
		shows.reach(console, library: library)
		shows.startDemo()
		
		for _ in 0..<300 where !shows.isLoaded {
			try await Task.sleep(for: .milliseconds(10))
		}
		
		#expect(shows.isLoaded)
		let context = shows.container.mainContext
		let undo = try #require(context.undoManager)
		var undone = 0
		var erased = 0
		var gone: [ShowContents.Cue] = []
		
		var fixtures: [Fixture] { (try? context.fetch(FetchDescriptor<Fixture>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? [] }
		var groups: [FixtureGroup] { (try? context.fetch(FetchDescriptor<FixtureGroup>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? [] }
		var looks: [Look] { (try? context.fetch(FetchDescriptor<Look>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? [] }
		var cues: [Cue] { (try? context.fetch(FetchDescriptor<Cue>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? [] }
		
		func pick<Item>(_ items: [Item]) -> Item? {
			items.isEmpty ? nil : items[roll(items.count)]
		}
		
		func remote(_ folder: NodeStore.Folder, _ id: String, _ body: Data?) {
			shows.take(body, at: Wire.Place(show: shows.activeID, folder: folder.rawValue, id: id), in: folder)
		}
		
		for step in 0..<500 {
			switch roll(18) {
			case 0: if let look = pick(looks) { look.name = "Local \(step)" }
			case 1: if let fixture = pick(fixtures) { fixture.address = 1 + roll(500) }
			case 2:
				if let fixture = pick(fixtures), let group = pick(groups) {
					fixture.belong(to: group, !fixture.belongs(to: group))
				}
			case 3: if let cue = pick(cues) { cue.label = "Cue \(step)" }
			case 4: _ = Look.fresh(among: looks, context: context)
			case 5:
				let group = FixtureGroup(name: "Group \(step)", sortIndex: Double(step))
				context.insert(group)
			case 6:
				if let cue = pick(cues) {
					gone.append(cue.entry)
					context.delete(cue)
				}
			case 7: if let fixture = pick(fixtures), roll(3) == 0 { context.delete(fixture) }
			case 8: if let look = pick(looks), roll(2) == 0 { console.remove(look, with: cues, context: context) }
			case 9:
				if let look = pick(looks) {
					erased += 1
					remote(.scenes, look.identifier, nil)
				}
			case 10:
				if let cue = pick(cues) {
					erased += 1
					remote(.cues, cue.identifier, nil)
				}
			case 11:
				if let fixture = pick(fixtures) {
					erased += 1
					remote(.lights, fixture.identifier, nil)
				}
			case 12:
				if let group = pick(groups) {
					erased += 1
					remote(.groups, group.identifier, nil)
				}
			case 13:
				var show = ShowContents()
				show.scenes = looks.prefix(1).map(\.entry)
				show.lights = fixtures.prefix(1).map(\.entry)
				show.cues = cues.prefix(1).map(\.entry)
				
				for index in show.scenes.indices {
					show.scenes[index].name = "Remote \(step)"
				}
				
				for index in show.lights.indices {
					show.lights[index].groups = groups.prefix(roll(3)).map(\.identifier)
				}
				
				for index in show.cues.indices {
					show.cues[index].label = "Remote \(step)"
				}
				
				for (key, body) in ShowLibrary.encoded(show, folders: ShowLibrary.everything) {
					let parts = key.split(separator: "/", maxSplits: 1)
					remote(try #require(NodeStore.Folder(rawValue: String(parts[0]))), String(parts[1]), body)
				}
			case 16, 17:
				if let entry = pick(gone) {
					remote(.cues, entry.identifier, entry.body)
				}
			default:
				if undo.canUndo {
					undone += 1
					undo.undo()
				}
			}
			
			try? context.save()
			try await Task.sleep(for: .milliseconds(1))
			
			for look in looks {
				_ = (look.entry, look.cues(among: cues))
			}
			
			for fixture in fixtures {
				_ = fixture.entry
			}
			
			for group in groups {
				_ = (group.entry, group.members.map(\.entry))
			}
			
			for cue in cues {
				_ = (cue.entry, cue.levels)
			}
		}
		
		#expect(undone > 20 && erased > 20)
		shows.stopDemo()
	}
}
