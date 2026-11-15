import Foundation
import SwiftData
import Testing

@testable import Glow

@MainActor
struct SessionTests {
	@Test(arguments: [UInt64(1), 2, 3, 4])
	func randomShowsWithDeletesFromOtherDevicesNeverLeaveTheStageOrTheScreensBroken(seed: UInt64) async throws {
		var state = seed &* 0x9E3779B97F4A7C15
		
		func roll(_ count: Int) -> Int {
			state = state &* 6364136223846793005 &+ 1442695040888963407
			return Int((state >> 33) % UInt64(max(count, 1)))
		}
		
		let wash = FixtureType(id: "wash", model: "Wash", channels: [FixtureChannel(offset: 1, attribute: .dimmer), FixtureChannel(offset: 2, attribute: .red), FixtureChannel(offset: 3, attribute: .green), FixtureChannel(offset: 4, attribute: .blue), FixtureChannel(offset: 5, attribute: .pan, fineOffset: 6, defaultValue: 128)])
		let library = FixtureLibrary(builtIn: [])
		library.setMade([wash])
		let container = try ModelContainer(for: Fixture.self, FixtureGroup.self, StoredFixtureType.self, Look.self, Cue.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
		let context = container.mainContext
		let console = Console()
		console.isMuted = true
		var seen: [Cue] = []
		var scenesSeen: [Look] = []
		
		for index in 0..<4 {
			context.insert(Fixture(typeID: "wash", name: "Light \(index)", address: DMXAddress([1, 7, 13, 509][index])!, sortIndex: Double(index)))
		}
		
		for index in 0..<3 {
			let look = Look.fresh(among: (try? context.fetch(FetchDescriptor<Look>())) ?? [], context: context)
			look.loops = index != 1
			scenesSeen.append(look)
		}
		
		var fixtures: [Fixture] { (try? context.fetch(FetchDescriptor<Fixture>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? [] }
		var looks: [Look] { (try? context.fetch(FetchDescriptor<Look>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? [] }
		var cues: [Cue] { (try? context.fetch(FetchDescriptor<Cue>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? [] }
		
		func synced() {
			try? context.save()
			console.applyPatch(fixtures, library: library)
			console.lists = Dictionary(CueList.all(looks, cues: cues, fixtures: fixtures).map { ($0.scene, $0) }, uniquingKeysWith: { first, _ in first })
		}
		
		func record(_ destination: Recording.Destination) {
			let recording = Recording(destination, console: console, fixtures: fixtures, library: library, looks: looks, cues: cues)
			recording.fade = [0, 0.05, 1][roll(3)]
			recording.follow = roll(3) == 0 ? 0.02 : nil
			_ = (recording.title, recording.number, recording.slot, recording.hint, recording.isReady, recording.isOnStage, recording.isDefault)
			recording.store(context: context)
		}
		
		synced()
		
		for look in looks {
			for _ in 0..<3 {
				for fixture in fixtures {
					console.set(UInt8(roll(256)), at: fixture.start)
				}
				
				record(.cue(look, after: look.cues(among: cues).last))
			}
		}
		
		synced()
		seen = cues
		
		for step in 0..<600 {
			let live = looks
			let look = live.isEmpty ? nil : live[roll(live.count)]
			let list = look.flatMap { console.lists[$0.identifier] }
			let stale = seen.isEmpty ? nil : seen[roll(seen.count)]
			let staleScene = scenesSeen[roll(scenesSeen.count)]
			
			switch roll(22) {
			case 0: if let list { console.toggle(list) }
			case 1: if let list { console.go(list) }
			case 2: if let list { console.back(list) }
			case 3:
				if let list {
					console.flash(list, isHeld: true)
					console.flash(list, isHeld: false)
				}
			case 4: if let list, !list.cues.isEmpty { console.play(list, at: roll(list.cues.count)) }
			case 5: if let list, !list.cues.isEmpty { console.land(list, at: roll(list.cues.count)) }
			case 6: if roll(4) == 0 { console.stopAll() } else if let list { console.stop(list) }
			case 7: if let list, let stale { console.arm(stale.identifier, of: list.scene) }
			case 8:
				if let stale, !stale.isDeleted {
					context.delete(stale)
					try? context.save()
				}
			case 9:
				if let look, let list {
					let held = look.cues(among: cues)
					if !held.isEmpty { console.delete([held[roll(held.count)]], from: list, context: context) }
				}
			case 10:
				if let look, roll(3) == 0 {
					look.remove(with: cues, context: context)
					try? context.save()
				}
			case 11: if let look, roll(3) == 0 { console.remove(look, with: cues, context: context) }
			case 12:
				if roll(4) == 0, let fixture = fixtures.randomElement() {
					context.delete(fixture)
					try? context.save()
				}
			case 13:
				for fixture in fixtures {
					console.set(UInt8(roll(256)), at: fixture.start)
				}
				
				record(.cue(roll(2) == 0 ? staleScene : look ?? staleScene, after: stale))
			case 14: if let stale { record(.into(stale)) }
			case 15:
				if let look {
					let held = look.cues(among: cues)
					let picked = held.filter { _ in roll(2) == 0 }
					
					switch roll(4) {
					case 0: if cues.count < 60 { console.duplicate(picked, among: held, context: context) }
					case 1: if let list, let other = live.randomElement() { console.move(picked, from: list, to: other, among: cues) }
					case 2: if cues.count < 60, let other = live.randomElement() { console.copy(picked, to: other, among: cues, context: context) }
					default:
						var end = CueDraft()
						end.fade = 0.03
						console.retime(picked, from: CueDraft(), to: end)
					}
				}
			case 16: if roll(3) == 0 { scenesSeen.append(Look.fresh(among: live, context: context)) }
			case 17:
				if let look {
					console.selection.build(look.identifier)
					console.keep(look, among: cues, fixtures: fixtures, library: library)
					
					for fixture in fixtures {
						console.set(UInt8(roll(256)), at: fixture.start)
					}
					
					if roll(2) == 0 { record(.cue(look, after: stale)) }
					_ = console.hasChanged(look, among: cues)
					
					if roll(2) == 0 {
						console.discard(look, among: cues, fixtures: fixtures, context: context)
					} else {
						console.selection.building = nil
					}
				}
			case 18: console.selection.marked = stale?.identifier
			case 19: if let stale { Recording(.into(stale), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues).show() }
			case 20: console.reset(among: fixtures, library: library)
			default: if let fixture = fixtures.randomElement() { console.set(UInt8(roll(256)), at: fixture.start) }
			}
			
			try await Task.sleep(for: .milliseconds(1))
			synced()
			try await Task.sleep(for: .milliseconds(1))
			seen.append(contentsOf: cues.filter { cue in !seen.contains { $0 === cue } })
			
			for look in looks {
				let list = try #require(console.lists[look.identifier])
				let held = look.cues(among: cues)
				let index = list.index(of: console.playback.cue(of: look.identifier))
				let upcoming = console.upcoming(list)
				#expect(list.cues.map(\.identifier) == held.map(\.identifier), "step \(step) the list and the cues disagree")
				#expect(index == nil || list.cues.indices.contains(index!), "step \(step)")
				#expect(upcoming == nil || list.cues.indices.contains(upcoming!), "step \(step) Go points past the cues")
				_ = (list.status(at: index), list.window(live: index, upcoming: upcoming).map(list.heading(at:)), console.isMoving(look.identifier), console.marked(among: held), index.flatMap(list.previous(before:)), look.slot, Board(columns: 4, looks: looks).rows)
				
				for action in SceneAction.allCases {
					_ = look.enables(action, live: index, upcoming: upcoming, list: list, isFlashing: false)
				}
			}
			
			try await Task.sleep(for: .milliseconds(1))
		}
		
		console.stopAll()
	}
}
