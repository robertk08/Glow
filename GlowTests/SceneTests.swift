import CoreGraphics
import Foundation
import SwiftData
import Testing

@testable import Glow

@MainActor
struct SceneTests {
	private static let wash = FixtureType(id: "wash", model: "Wash", channels: [
		FixtureChannel(offset: 1, attribute: .dimmer),
		FixtureChannel(offset: 2, attribute: .red),
		FixtureChannel(offset: 3, attribute: .green),
		FixtureChannel(offset: 4, attribute: .blue),
		FixtureChannel(offset: 5, attribute: .pan, fineOffset: 6, defaultValue: 128),
		FixtureChannel(offset: 7, attribute: .gobo),
	])
	
	private static let head = FixtureType(id: "head", model: "Head", channels: [
		FixtureChannel(offset: 1, attribute: .shutter, functions: [
			ChannelFunction(from: 0, to: 7, label: "Closed", purpose: .closed),
			ChannelFunction(from: 8, to: 134, label: "Dimmer", kind: .proportional, purpose: .dim),
			ChannelFunction(from: 135, to: 239, label: "Strobe", kind: .proportional),
			ChannelFunction(from: 240, to: 255, label: "Open", purpose: .open),
		]),
	])
	
	@MainActor private struct Rig {
		let console: Console
		let library: FixtureLibrary
		let container: ModelContainer
		let fixtures: [Fixture]
		let look: Look
		
		var context: ModelContext { container.mainContext }
		var cues: [Cue] { (try? context.fetch(FetchDescriptor<Cue>())) ?? [] }
		var looks: [Look] { (try? context.fetch(FetchDescriptor<Look>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? [] }
		var list: CueList { CueList(look, cues: cues, fixtures: fixtures) }
		
		func value(_ address: Int) -> UInt8 {
			console.value(at: DMXAddress(address)!)
		}
		
		func list(of look: Look) -> CueList {
			CueList(look, cues: cues, fixtures: fixtures)
		}
		
		@discardableResult func add(_ sortIndex: Double, fade: Double = 0, to look: Look? = nil, _ values: [(light: Int, slot: Int, value: UInt8)]) -> Cue {
			var levels = Levels()
			
			for value in values {
				levels.set(value.value, slot: value.slot, of: fixtures[value.light].identifier)
			}
			
			let cue = Cue(lookID: (look ?? self.look).identifier, sortIndex: sortIndex, fade: fade, levels: levels)
			context.insert(cue)
			try? context.save()
			return cue
		}
		
		func recording(_ destination: Recording.Destination) -> Recording {
			Recording(destination, console: console, fixtures: fixtures, library: library, looks: looks, cues: cues)
		}
	}
	
	private func rig() throws -> Rig {
		let library = FixtureLibrary(builtIn: [])
		library.setMade([Self.wash, Self.head])
		let container = try ModelContainer(for: Fixture.self, FixtureGroup.self, StoredFixtureType.self, Look.self, Cue.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
		let fixtures = [
			Fixture(typeID: "wash", name: "Left", address: DMXAddress(1)!, sortIndex: 0),
			Fixture(typeID: "wash", name: "Right", address: DMXAddress(11)!, sortIndex: 1),
			Fixture(typeID: "head", name: "Head", address: DMXAddress(21)!, sortIndex: 2),
		]
		let look = Look(name: "Play", sortIndex: 0)
		
		for fixture in fixtures {
			container.mainContext.insert(fixture)
		}
		
		container.mainContext.insert(look)
		try container.mainContext.save()
		let console = Console()
		console.isMuted = true
		console.applyPatch(fixtures, library: library)
		return Rig(console: console, library: library, container: container, fixtures: fixtures, look: look)
	}
	
	private func wall(renaming odd: Int? = nil, slots: ClosedRange<Int> = 1...512) throws -> (Console, CueList) {
		let library = FixtureLibrary(builtIn: [])
		library.setMade([FixtureType(id: "wall", model: "Wall", channels: (1...512).map { FixtureChannel(offset: $0, attribute: .red) })])
		let container = try ModelContainer(for: Fixture.self, FixtureGroup.self, StoredFixtureType.self, Look.self, Cue.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
		let wall = Fixture(typeID: "wall", name: "Wall", address: DMXAddress(1)!, sortIndex: 0)
		let look = Look(name: "Chase", sortIndex: 0)
		look.loops = true
		wall.identifier = "wall"
		look.identifier = "chase"
		container.mainContext.insert(wall)
		container.mainContext.insert(look)
		
		for step in 1...30 {
			var levels = Levels()
			
			for slot in slots {
				levels.set(UInt8(step), slot: slot, of: wall.identifier)
			}
			
			let cue = Cue(lookID: look.identifier, sortIndex: Double(step), fade: 0, levels: levels)
			cue.follow = 0.03
			cue.identifier = "cue\(step)"
			if step == odd { cue.identifier = String(repeating: "y", count: 60) }
			container.mainContext.insert(cue)
		}
		
		try container.mainContext.save()
		let console = Console()
		console.isMuted = true
		console.applyPatch([wall], library: library)
		return (console, CueList(look, cues: try container.mainContext.fetch(FetchDescriptor<Cue>()), fixtures: [wall]))
	}
	
	private func settled(_ console: Console, scene: String) async throws -> String? {
		var previous: String?
		
		for _ in 0..<50 {
			try await Task.sleep(for: .milliseconds(100))
			let current = console.playback.cue(of: scene)
			if current == previous, console.playback.playing.first?.wants == true { return current }
			previous = current
		}
		
		Issue.record("the chase never came to rest")
		return previous
	}
	
	private func until(within seconds: Double = 3, _ condition: () -> Bool) async throws {
		let start = Date()
		
		while Date().timeIntervalSince(start) < seconds {
			if condition() { return }
			try await Task.sleep(for: .milliseconds(5))
		}
		
		#expect(condition(), "timed out")
	}
	
	@Test func aSceneTurnedOffPutsItsLightsBack() async throws {
		let rig = try rig()
		rig.console.set(40, at: DMXAddress(1)!)
		rig.add(1, [(0, 1, 255), (0, 2, 200)])
		
		rig.console.toggle(rig.list)
		try await until { rig.value(1) == 255 && rig.value(2) == 200 }
		#expect(rig.console.playback.cue(of: rig.look.identifier) != nil)
		
		rig.console.toggle(rig.list)
		try await until { rig.value(1) == 40 && rig.value(2) == 0 }
		#expect(rig.console.playback.cue(of: rig.look.identifier) == nil)
	}
	
	@Test func turningOneSceneOffLeavesTheOtherOneHolding() async throws {
		let rig = try rig()
		let other = Look(name: "Other", sortIndex: 1)
		rig.context.insert(other)
		rig.add(1, [(0, 1, 100), (1, 1, 100)])
		rig.add(1, to: other, [(0, 1, 200)])
		
		rig.console.toggle(rig.list)
		try await until { rig.value(1) == 100 && rig.value(11) == 100 }
		rig.console.toggle(rig.list(of: other))
		try await until { rig.value(1) == 200 }
		
		rig.console.toggle(rig.list)
		try await until { rig.value(11) == 0 }
		#expect(rig.value(1) == 200)
		
		rig.console.toggle(rig.list(of: other))
		try await until { rig.value(1) == 0 }
	}
	
	@Test func cuesStepForwardAndBackAndValuesCarryThrough() async throws {
		let rig = try rig()
		let first = rig.add(1, [(0, 1, 255), (0, 2, 255)])
		let second = rig.add(2, [(0, 2, 0), (1, 1, 90)])
		
		rig.console.go(rig.list)
		try await until { rig.console.playback.cue(of: rig.look.identifier) == first.identifier && rig.value(2) == 255 }
		
		rig.console.go(rig.list)
		try await until { rig.console.playback.cue(of: rig.look.identifier) == second.identifier && rig.value(2) == 0 && rig.value(11) == 90 }
		#expect(rig.value(1) == 255)
		
		rig.console.back(rig.list)
		try await until { rig.value(2) == 255 && rig.value(11) == 0 }
	}
	
	@Test func afterTheLastCueGoWaitsUnlessTheSceneLoops() async throws {
		let rig = try rig()
		let first = rig.add(1, [(0, 1, 10)])
		let second = rig.add(2, [(0, 1, 20)])
		
		rig.console.go(rig.list)
		rig.console.go(rig.list)
		try await until { rig.console.playback.cue(of: rig.look.identifier) == second.identifier }
		
		#expect(rig.console.upcoming(rig.list) == nil)
		
		rig.console.go(rig.list)
		
		#expect(rig.console.playback.cue(of: rig.look.identifier) == second.identifier)
		
		rig.look.loops = true
		rig.console.go(rig.list)
		try await until { rig.console.playback.cue(of: rig.look.identifier) == first.identifier && rig.value(1) == 10 }
		
		rig.console.back(rig.list)
		try await until { rig.console.playback.cue(of: rig.look.identifier) == second.identifier && rig.value(1) == 20 }
	}
	
	@Test func aCueWithAFollowRunsTheNextOneByItselfAfterItsDelay() async throws {
		let rig = try rig()
		let first = rig.add(1, [(0, 1, 10)])
		let second = rig.add(2, [(0, 1, 20)])
		let third = rig.add(3, [(0, 1, 30)])
		first.delay = 0.1
		first.follow = 0.1
		second.follow = 0
		try rig.context.save()
		
		let started = Date()
		rig.console.go(rig.list)
		try await until { rig.console.playback.cue(of: rig.look.identifier) == third.identifier && rig.value(1) == 30 }
		#expect(Date().timeIntervalSince(started) >= 0.2)
		try await Task.sleep(for: .milliseconds(150))
		#expect(rig.console.playback.cue(of: rig.look.identifier) == third.identifier)
	}
	
	@Test func aFlashHoldsOnlyWhileHeldAndIgnoresTheFade() async throws {
		let rig = try rig()
		rig.console.set(40, at: DMXAddress(1)!)
		rig.add(1, fade: 5, [(0, 1, 255)])
		
		rig.console.flash(rig.list, isHeld: true)
		try await until { rig.value(1) == 255 }
		
		rig.console.flash(rig.list, isHeld: false)
		try await until { rig.value(1) == 40 }
		#expect(rig.console.playback.playing.isEmpty)
	}
	
	@Test func jumpingToACueSetsWhatItAndTheCuesBeforeHold() async throws {
		let rig = try rig()
		rig.add(1, [(0, 1, 10)])
		rig.add(2, [(0, 2, 20)])
		let third = rig.add(3, [(0, 3, 30)])
		
		rig.console.play(rig.list, at: 2)
		try await until { rig.value(1) == 10 && rig.value(2) == 20 && rig.value(3) == 30 }
		#expect(rig.console.playback.cue(of: rig.look.identifier) == third.identifier)
	}
	
	@Test func aFadeGlidesWhileDiscreteChannelsSnap() async throws {
		let rig = try rig()
		rig.add(1, fade: 3, [(0, 1, 200), (0, 7, 60)])
		
		rig.console.go(rig.list)
		var between: [(dimmer: UInt8, gobo: UInt8)] = []
		
		while rig.value(1) != 200 {
			if (1...199).contains(rig.value(1)) { between.append((rig.value(1), rig.value(7))) }
			try await Task.sleep(for: .milliseconds(5))
		}
		
		#expect(!between.isEmpty)
		#expect(between.allSatisfy { $0.gobo == 60 })
	}
	
	@Test func aSixteenBitChannelFadesAsOneValue() async throws {
		let rig = try rig()
		rig.console.set(0, at: DMXAddress(5)!)
		rig.add(1, fade: 3, [(0, 5, 255), (0, 6, 255)])
		
		rig.console.go(rig.list)
		var coarse: Set<UInt8> = []
		
		while rig.value(6) != 255 || rig.value(5) != 255 {
			coarse.insert(rig.value(5))
			try await Task.sleep(for: .milliseconds(5))
		}
		
		#expect(coarse.contains { (40...230).contains($0) })
	}
	
	@Test func aBandDimmerFadesInsideItsBandRatherThanThroughTheStrobe() async throws {
		let rig = try rig()
		rig.add(1, fade: 3, [(2, 1, 240)])
		
		rig.console.go(rig.list)
		var seen: Set<UInt8> = []
		
		while rig.value(21) != 240 {
			seen.insert(rig.value(21))
			try await Task.sleep(for: .milliseconds(5))
		}
		
		#expect(seen.contains { (8...134).contains($0) })
		#expect(!seen.contains { (135...239).contains($0) })
	}
	
	@Test func theProgrammerTakesAChannelOverMidFade() async throws {
		let rig = try rig()
		rig.add(1, fade: 0.4, [(0, 1, 200), (0, 2, 180)])
		
		rig.console.go(rig.list)
		try await Task.sleep(for: .milliseconds(100))
		rig.console.set(50, at: DMXAddress(1)!)
		try await until { rig.value(2) == 180 }
		try await Task.sleep(for: .milliseconds(100))
		
		#expect(rig.value(1) == 50)
	}
	
	@Test func aCueWithADelayLetsTheFadeBeforeItRunOnUntilItStarts() async throws {
		let rig = try rig()
		rig.add(1, fade: 3, [(0, 1, 250)])
		rig.add(2, fade: 1, [(0, 1, 0)]).delay = 1
		
		rig.console.go(rig.list)
		try await until { (40...120).contains(rig.value(1)) }
		rig.console.go(rig.list)
		let paused = rig.value(1)
		try await Task.sleep(for: .milliseconds(500))
		
		#expect(Int(rig.value(1)) > Int(paused) + 20)
		try await until(within: 5) { rig.value(1) == 0 }
	}
	
	@Test func aSceneStoresOnlyTheLightsAndAspectsChosen() throws {
		let rig = try rig()
		rig.console.set(255, at: DMXAddress(1)!)
		rig.console.set(90, at: DMXAddress(13)!)
		let fresh = Look.fresh(among: rig.looks, context: rig.context)
		let recording = rig.recording(.cue(fresh, after: nil))
		
		#expect(fresh.name == "Scene 2")
		#expect(recording.number == 1)
		#expect(recording.hint == "All lights")
		#expect(recording.lights == Set(rig.fixtures.map(\.identifier)))
		
		recording.lights = [rig.fixtures[0].identifier]
		recording.toggle(.position)
		
		#expect(recording.levels.lights[rig.fixtures[0].identifier]?.keys.sorted() == [1, 2, 3, 4, 7])
		
		recording.store(context: rig.context)
		
		#expect(rig.looks.count == 2)
		#expect(fresh.cues(among: rig.cues).count == 1)
		#expect(!rig.console.isActive(DMXAddress(1)!))
	}
	
	@Test func aStoreTakesEveryLightWhateverIsSelected() throws {
		let rig = try rig()
		rig.console.set(120, at: DMXAddress(11)!)
		rig.console.selection.toggle(rig.fixtures[0])
		let recording = rig.recording(.cue(rig.look, after: nil))
		
		#expect(recording.lights == Set(rig.fixtures.map(\.identifier)))
		#expect(recording.hint == "All lights")
		
		recording.lights = [rig.fixtures[1].identifier]
		rig.console.selection.toggle(rig.fixtures[2])
		
		#expect(rig.recording(.cue(rig.look, after: nil)).lights == [rig.fixtures[1].identifier])
	}
	
	@Test func deletingTheLiveCueMovesTheStageToTheOneBefore() throws {
		let rig = try rig()
		rig.add(1, [(0, 1, 10)])
		let second = rig.add(2, [(0, 1, 20)])
		rig.console.play(rig.list, at: 1, snapping: true)
		rig.console.delete([second], from: rig.list, context: rig.context)
		
		let held = rig.look.cues(among: rig.cues)
		#expect(held.count == 1)
		#expect(rig.console.playback.cue(of: rig.look.identifier) == held[0].identifier)
		
		rig.console.delete([held[0]], from: rig.list, context: rig.context)
		
		#expect(rig.console.playback.cue(of: rig.look.identifier) == nil)
	}
	
	@Test func updateStoresWhatChangedOnAnyLightWhateverIsSelected() throws {
		let rig = try rig()
		let cue = rig.add(1, [(0, 1, 200)])
		rig.console.play(rig.list, at: 0, snapping: true)
		rig.console.set(70, at: DMXAddress(11)!)
		rig.console.set(50, at: DMXAddress(2)!)
		rig.console.set(0, at: DMXAddress(2)!)
		rig.console.selection.toggle(rig.fixtures[0])
		
		#expect(rig.recording(.cue(rig.look, after: cue)).hint == "All lights")
		
		rig.recording(.into(cue)).store(context: rig.context)
		
		#expect(cue.levels.lights[rig.fixtures[1].identifier] == [1: 70])
		#expect(cue.levels.lights[rig.fixtures[0].identifier] == [1: 200])
		#expect(!rig.console.selection.isEmpty)
		#expect(!rig.recording(.into(cue)).isReady)
	}
	
	@Test func updateIsOnlyReadyWhileTheStageDiffersFromTheCue() throws {
		let rig = try rig()
		let cue = rig.add(1, [(0, 1, 0)])
		rig.console.set(255, at: DMXAddress(1)!)
		
		#expect(rig.recording(.into(cue)).isReady)
		
		rig.console.set(0, at: DMXAddress(1)!)
		
		#expect(!rig.recording(.into(cue)).isReady)
		#expect(rig.console.isActive(DMXAddress(1)!))
		
		rig.console.set(90, at: DMXAddress(11)!)
		rig.console.set(0, at: DMXAddress(11)!)
		
		#expect(!rig.recording(.into(cue)).isReady)
	}
	
	@Test func afterUpdatingOneCueTheNextCueCanStillBeUpdatedToWhatIsOnStage() throws {
		let rig = try rig()
		let first = rig.add(1, [(0, 1, 0), (1, 1, 0)])
		let second = rig.add(2, [(0, 1, 0), (1, 1, 0)])
		rig.console.set(128, at: DMXAddress(1)!)
		rig.console.set(128, at: DMXAddress(11)!)
		rig.recording(.into(first)).store(context: rig.context)
		
		#expect(!rig.recording(.into(first)).isReady)
		#expect(rig.recording(.into(second)).isReady)
		
		rig.recording(.into(second)).store(context: rig.context)
		
		#expect(second.levels.lights[rig.fixtures[0].identifier]?[1] == 128)
		#expect(second.levels.lights[rig.fixtures[1].identifier]?[1] == 128)
		#expect(!rig.recording(.into(first)).isReady)
		#expect(!rig.recording(.into(second)).isReady)
	}
	
	@Test func afterUpdatingOneSceneAnotherSceneCanStillBeUpdatedToWhatIsOnStage() throws {
		let rig = try rig()
		let other = Look.fresh(among: rig.looks, context: rig.context)
		let first = rig.add(1, [(0, 1, 0), (1, 1, 0)])
		let second = rig.add(1, to: other, [(0, 1, 0), (1, 1, 0)])
		rig.console.set(128, at: DMXAddress(1)!)
		rig.console.set(128, at: DMXAddress(11)!)
		rig.recording(.into(first)).store(context: rig.context)
		
		#expect(rig.recording(.into(second)).isReady)
		
		rig.recording(.into(second)).store(context: rig.context)
		
		#expect(second.levels.lights[rig.fixtures[0].identifier]?[1] == 128)
		#expect(!rig.recording(.into(second)).isReady)
	}
	
	@Test func showingACueMakesTheStageThatCueAndLeavesOtherTouchesAlone() throws {
		let rig = try rig()
		let first = rig.add(1, [(0, 1, 10)])
		rig.add(2, [(0, 1, 20), (1, 1, 30)])
		rig.console.land(rig.list, at: 1)
		rig.console.set(99, at: DMXAddress(1)!)
		rig.console.set(50, at: DMXAddress(21)!)
		
		#expect(!rig.recording(.into(first)).isOnStage)
		
		rig.recording(.into(first)).show()
		
		#expect(rig.value(1) == 10)
		#expect(rig.value(21) == 50)
		#expect(rig.recording(.into(first)).isOnStage)
		#expect(rig.console.playback.cue(of: rig.look.identifier) == first.identifier)
		#expect(!rig.console.isActive(DMXAddress(1)!))
		#expect(rig.recording(.into(first)).isReady)
		#expect(rig.recording(.into(first)).levels.lights.keys.sorted() == [rig.fixtures[2].identifier])
	}
	
	@Test func randomArrangingPutsTheTileUnderTheFingerAndSlidesOnlyCoveredTilesStraightDown() async throws {
		var seed: UInt64 = 0x2545F4914F6CDD1D
		
		func roll(_ count: Int) -> Int {
			seed = seed &* 6364136223846793005 &+ 1442695040888963407
			return Int((seed >> 33) % UInt64(count))
		}
		
		let rig = try rig()
		let sizes: [TileSize] = [.small, .small, .wide, .large, .small, .wide, .small]
		
		for size in sizes {
			let look = Look.fresh(among: rig.looks, context: rig.context)
			look.size = size
		}
		
		let arrangement = Arrangement()
		arrangement.width = 352
		let columns = arrangement.columns
		
		func place(_ looks: [Look]) -> [String: Int] {
			let origins = TileLayout.origins(of: looks.map(\.size), at: looks.map { arrangement.slot(of: $0) }, columns: columns)
			
			for (look, origin) in zip(looks, origins) {
				let across = min(look.size.columns, columns)
				arrangement.frames[look.identifier] = CGRect(x: Double(origin % columns) * 182, y: Double(origin / columns) * 112, width: Double(across) * 170 + Double(across - 1) * 12, height: Double(look.size.rows) * 100 + Double(look.size.rows - 1) * 12)
			}
			
			return Dictionary(uniqueKeysWithValues: zip(looks.map(\.identifier), origins))
		}
		
		for session in 0..<300 {
			try await Task.sleep(for: .milliseconds(1))
			let looks = arrangement.arranged(rig.looks)
			let before = place(looks)
			let indexes = rig.looks.map(\.sortIndex)
			let lifted = looks[roll(looks.count)]
			let start = arrangement.frames[lifted.identifier]!
			arrangement.lift(lifted.identifier, at: CGPoint(x: start.midX, y: start.midY), among: looks)
			
			for _ in 0..<roll(8) {
				arrangement.drag(to: CGPoint(x: Double(roll(360)), y: Double(roll(900))))
				#expect(rig.looks.map(\.sortIndex) == indexes, "session \(session) wrote while dragging")
			}
			
			let shown = Dictionary(uniqueKeysWithValues: looks.map { ($0.identifier, arrangement.slot(of: $0)) })
			arrangement.drop(among: looks)
			try? rig.context.save()
			let after = place(arrangement.arranged(rig.looks))
			let moved = before.keys.filter { before[$0] != after[$0] }
			#expect(after == shown, "session \(session) landed somewhere other than where it was shown")
			let landed = Set(TileLayout.cells(of: lifted.size, at: after[lifted.identifier]!, columns: columns))
			
			for other in moved where other != lifted.identifier {
				let size = rig.looks.first { $0.identifier == other }!.size
				#expect(!landed.isDisjoint(with: TileLayout.cells(of: size, at: before[other]!, columns: columns)), "session \(session) moved a tile the drop did not cover")
				#expect(after[other]! > before[other]! && after[other]! % columns == before[other]! % columns, "session \(session) moved a covered tile other than straight down")
				
				var higher = after[other]! - columns
				
				while higher > before[other]! {
					let cells = Set(TileLayout.cells(of: size, at: higher, columns: columns))
					let blocked = rig.looks.contains { look in look.identifier != other && !cells.isDisjoint(with: TileLayout.cells(of: look.size, at: after[look.identifier]!, columns: columns)) }
					#expect(blocked, "session \(session) slid a tile further down than it had to")
					higher -= columns
				}
			}
			
			if moved.isEmpty {
				#expect(rig.looks.map(\.sortIndex) == indexes, "session \(session) wrote without a move")
			}
			
			var cells = Set<Int>()
			
			for look in rig.looks {
				let covered = TileLayout.cells(of: look.size, at: after[look.identifier]!, columns: columns)
				#expect(cells.isDisjoint(with: covered), "session \(session) put two tiles on one spot")
				cells.formUnion(covered)
			}
		}
	}
	
	@Test func randomResizingChangesOnlyThatTileAndSlidesOnlyCoveredTilesStraightDown() async throws {
		var seed: UInt64 = 0x9E3779B97F4A7C15
		
		func roll(_ count: Int) -> Int {
			seed = seed &* 6364136223846793005 &+ 1442695040888963407
			return Int((seed >> 33) % UInt64(count))
		}
		
		let rig = try rig()
		
		for size in [TileSize.small, .wide, .small, .large, .small, .small, .wide] {
			let look = Look.fresh(among: rig.looks, context: rig.context)
			look.size = size
		}
		
		let arrangement = Arrangement()
		arrangement.width = 352
		let columns = arrangement.columns
		
		func place(_ looks: [Look]) -> [String: Int] {
			let origins = TileLayout.origins(of: looks.map { arrangement.size(of: $0) }, at: looks.map { arrangement.slot(of: $0) }, columns: columns)
			
			for (look, origin) in zip(looks, origins) {
				let size = arrangement.size(of: look)
				let across = min(size.columns, columns)
				arrangement.frames[look.identifier] = CGRect(x: Double(origin % columns) * 182, y: Double(origin / columns) * 112, width: Double(across) * 170 + Double(across - 1) * 12, height: Double(size.rows) * 100 + Double(size.rows - 1) * 12)
			}
			
			return Dictionary(uniqueKeysWithValues: zip(looks.map(\.identifier), origins))
		}
		
		for session in 0..<100 {
			try await Task.sleep(for: .milliseconds(1))
			let looks = arrangement.arranged(rig.looks)
			let before = place(looks)
			let sizes = Dictionary(uniqueKeysWithValues: rig.looks.map { ($0.identifier, $0.size) })
			let indexes = rig.looks.map(\.sortIndex)
			let stretched = looks[roll(looks.count)]
			
			for _ in 0...roll(6) {
				arrangement.stretch(stretched.identifier, by: CGSize(width: Double(roll(400)) - 200, height: Double(roll(400)) - 200), among: looks)
				_ = place(arrangement.arranged(looks))
				#expect(rig.looks.map(\.sortIndex) == indexes && rig.looks.allSatisfy { $0.size == sizes[$0.identifier] }, "session \(session) wrote while resizing")
			}
			
			let shown = place(arrangement.arranged(looks))
			arrangement.settle(among: looks)
			try? rig.context.save()
			let after = place(arrangement.arranged(rig.looks))
			#expect(after == shown, "session \(session) landed somewhere other than where it was shown")
			#expect(rig.looks.allSatisfy { $0.identifier == stretched.identifier || $0.size == sizes[$0.identifier] }, "session \(session) resized another tile")
			let grown = Set(TileLayout.cells(of: stretched.size, at: after[stretched.identifier]!, columns: columns))
			
			for look in rig.looks where look.identifier != stretched.identifier && after[look.identifier] != before[look.identifier] {
				#expect(!grown.isDisjoint(with: TileLayout.cells(of: look.size, at: before[look.identifier]!, columns: columns)), "session \(session) moved a tile the new size did not cover")
				#expect(after[look.identifier]! > before[look.identifier]! && after[look.identifier]! % columns == before[look.identifier]! % columns, "session \(session) moved a covered tile other than straight down")
			}
			
			var cells = Set<Int>()
			
			for look in rig.looks {
				let covered = TileLayout.cells(of: look.size, at: after[look.identifier]!, columns: columns)
				#expect(cells.isDisjoint(with: covered), "session \(session) put two tiles on one spot")
				cells.formUnion(covered)
			}
		}
	}
	
	@Test func deletingSeveralCuesWithTheLiveOneMovesTheStageToTheNearestKeptCueBefore() throws {
		let rig = try rig()
		
		for index in 1...5 {
			rig.add(Double(index), [(0, 1, UInt8(index * 10))])
		}
		
		let held = rig.look.cues(among: rig.cues)
		rig.console.play(rig.list, at: 3)
		rig.console.delete([held[2], held[3]], from: rig.list, context: rig.context)
		try rig.context.save()
		
		#expect(rig.look.cues(among: rig.cues).map(\.identifier) == [held[0], held[1], held[4]].map(\.identifier))
		#expect(rig.console.playback.cue(of: rig.look.identifier) == held[1].identifier)
		
		rig.console.delete(rig.look.cues(among: rig.cues), from: rig.list, context: rig.context)
		#expect(rig.console.playback.cue(of: rig.look.identifier) == nil)
	}
	
	@Test func duplicatingSeveralCuesPutsTheCopiesInOrderAfterTheLastOne() throws {
		let rig = try rig()
		
		for index in 1...4 {
			let cue = rig.add(Double(index), [(0, 1, UInt8(index))])
			cue.label = "\(index)"
		}
		
		let held = rig.look.cues(among: rig.cues)
		rig.console.duplicate([held[0], held[2]], among: held, context: rig.context)
		try rig.context.save()
		let after = rig.look.cues(among: rig.cues)
		
		#expect(after.map(\.label) == ["1", "2", "3", "1", "3", "4"])
		#expect(Set(after.map(\.identifier)).count == 6)
		#expect(after[3].levels == held[0].levels && after[4].levels == held[2].levels)
	}
	
	@Test func movingCuesToAnotherSceneAppendsThemInOrderAndLeavesTheStageOnAKeptCue() throws {
		let rig = try rig()
		let other = Look.fresh(among: rig.looks, context: rig.context)
		rig.add(1, to: other, [(1, 1, 9)])
		
		for index in 1...3 {
			let cue = rig.add(Double(index), [(0, 1, UInt8(index))])
			cue.label = "\(index)"
		}
		
		let held = rig.look.cues(among: rig.cues)
		rig.console.play(rig.list, at: 2)
		rig.console.move([held[1], held[2]], from: rig.list, to: other, among: rig.cues)
		try rig.context.save()
		
		#expect(rig.look.cues(among: rig.cues).map(\.label) == ["1"])
		#expect(other.cues(among: rig.cues).map(\.label) == ["", "2", "3"])
		#expect(rig.console.playback.cue(of: rig.look.identifier) == held[0].identifier)
	}
	
	@Test func timingSeveralCuesChangesOnlyWhatWasChanged() throws {
		let rig = try rig()
		let first = rig.add(1, fade: 2, [(0, 1, 1)])
		let second = rig.add(2, fade: 5, [(0, 1, 2)])
		second.delay = 1
		let start = CueDraft(fade: 2, delay: 0, follow: nil)
		var end = start
		end.follow = 0.5
		rig.console.retime([first, second], from: start, to: end)
		
		#expect(first.fade == 2 && second.fade == 5 && second.delay == 1)
		#expect(first.follow == 0.5 && second.follow == 0.5)
		
		let mixed = CueDraft(fade: -1, delay: -1, follow: 0.5)
		var nothing = mixed
		nothing.follow = nil
		rig.console.retime([first, second], from: mixed, to: nothing)
		
		#expect(first.fade == 2 && second.fade == 5 && second.delay == 1 && first.delay == 0)
		#expect(first.follow == nil && second.follow == nil)
	}
	
	@Test func aCueKeepsOnlyTheLightsAndAspectsLeftTickedAndGetsThemBackWhenTickedAgain() throws {
		let rig = try rig()
		let cue = rig.add(1, [(0, 1, 200), (0, 2, 10), (0, 3, 20), (0, 5, 30), (0, 6, 31), (1, 1, 100), (2, 1, 150)])
		let original = cue.levels
		let types = Dictionary(uniqueKeysWithValues: rig.fixtures.map { ($0.identifier, rig.library.type($0.typeID)!) })
		let all = Set(rig.fixtures.map(\.identifier))
		
		let colourless = original.keeping(all, features: Set(FeatureGroup.allCases).subtracting([.color]), types: types)
		#expect(colourless.lights[rig.fixtures[0].identifier] == [1: 200, 5: 30, 6: 31])
		#expect(colourless.lights[rig.fixtures[1].identifier] == [1: 100])
		
		let dark = original.keeping(all, features: Set(FeatureGroup.allCases).subtracting([.dimmer]), types: types)
		#expect(dark.lights[rig.fixtures[0].identifier] == [2: 10, 3: 20, 5: 30, 6: 31])
		#expect(dark.lights[rig.fixtures[1].identifier] == nil)
		#expect(dark.lights[rig.fixtures[2].identifier] == nil)
		
		let alone = original.keeping([rig.fixtures[1].identifier], features: Set(FeatureGroup.allCases), types: types)
		#expect(Set(alone.lights.keys) == [rig.fixtures[1].identifier])
		#expect(original.keeping(all, features: Set(FeatureGroup.allCases), types: types) == original)
	}
	
	@Test func aLargeTileShowsTheLiveCueThenWhatGoPlaysNext() throws {
		let rig = try rig()
		
		for index in 1...4 {
			rig.add(Double(index), [(0, 1, UInt8(index))])
		}
		
		#expect(rig.list.window(live: nil, upcoming: 0) == [0, 1, 2])
		#expect(rig.list.window(live: 1, upcoming: 2) == [1, 2, 3])
		#expect(rig.list.window(live: 1, upcoming: 3) == [1, 3])
		#expect(rig.list.window(live: 3, upcoming: nil) == [3])
		rig.look.loops = true
		#expect(rig.list.window(live: 3, upcoming: 0) == [3, 0, 1])
		#expect(rig.list.window(live: 2, upcoming: 3) == [2, 3, 0])
	}
	
	@Test func addingCuesToAnotherSceneWhileBuildingKeepsTheOpenBuilder() throws {
		let rig = try rig()
		let other = Look.fresh(among: rig.looks, context: rig.context)
		rig.console.selection.section = "scenes"
		rig.console.selection.build(rig.look.identifier)
		rig.console.selection.section = "scenes"
		rig.console.selection.build(other.identifier)
		
		#expect(rig.console.selection.building == rig.look.identifier)
		#expect(rig.console.selection.section == "lights")
	}
	
	@Test func deletingTheMarkedCueMarksTheOneBeforeIt() throws {
		let rig = try rig()
		let first = rig.add(1, [(0, 1, 10)])
		let second = rig.add(2, [(0, 1, 20)])
		rig.add(3, [(0, 1, 30)])
		rig.console.selection.marked = second.identifier
		rig.console.delete([second], from: rig.list, context: rig.context)
		
		#expect(rig.console.selection.marked == first.identifier)
		
		try? rig.context.save()
		rig.console.delete([first], from: rig.list, context: rig.context)
		
		#expect(rig.console.selection.marked == rig.look.cues(among: rig.cues).last?.identifier)
	}
	
	@Test func aDeletedLightLeavesTheStoreSettings() throws {
		let rig = try rig()
		let recording = rig.recording(.cue(rig.look, after: nil))
		recording.lights = [rig.fixtures[0].identifier, "gone"]
		
		#expect(rig.recording(.cue(rig.look, after: nil)).lights == [rig.fixtures[0].identifier])
		#expect(rig.recording(.cue(rig.look, after: nil)).hint == "1 light")
		
		recording.lights = []
		
		#expect(rig.recording(.cue(rig.look, after: nil)).hint == "No lights")
	}
	
	@Test func aBlankCueLabelReadsAsNoLabel() throws {
		let rig = try rig()
		let cue = rig.add(1, [(0, 1, 10)])
		cue.label = " \n "
		cue.settleLabel()
		
		#expect(cue.label.isEmpty)
		#expect(rig.list.heading(at: 0) == "Cue 1")
		
		let recording = rig.recording(.cue(rig.look, after: cue))
		recording.label = "\n Storm \n"
		recording.store(context: rig.context)
		
		#expect(rig.look.cues(among: rig.cues)[1].label == "Storm")
	}
	
	@Test func discardingAnEmptySceneTheBuilderDidNotCreateKeepsIt() throws {
		let rig = try rig()
		rig.console.selection.build(rig.look.identifier)
		rig.console.keep(rig.look, among: rig.cues, fixtures: rig.fixtures, library: rig.library)
		rig.look.name = "Renamed"
		
		#expect(rig.console.hasChanged(rig.look, among: rig.cues))
		
		rig.console.discard(rig.look, among: rig.cues, fixtures: rig.fixtures, context: rig.context)
		
		#expect(rig.looks.contains { $0.identifier == rig.look.identifier })
		#expect(rig.look.name == "Play")
	}
	
	@Test func discardingAfterOnlyARenameLeavesARunningSceneAlone() throws {
		let rig = try rig()
		rig.add(1, [(0, 1, 10)]).follow = 0
		rig.add(2, [(0, 1, 20)])
		rig.console.play(rig.list, at: 0)
		let playing = rig.console.playback.cue(of: rig.look.identifier)
		rig.console.selection.build(rig.look.identifier)
		rig.console.keep(rig.look, among: rig.cues, fixtures: rig.fixtures, library: rig.library)
		rig.look.name = "Renamed"
		rig.console.discard(rig.look, among: rig.cues, fixtures: rig.fixtures, context: rig.context)
		
		#expect(rig.console.playback.cue(of: rig.look.identifier) == playing)
		#expect(rig.console.playback.fades[rig.look.identifier]?.follows != false)
	}
	
	@Test func aRunningFadeOrFollowCountsAsMovingAndASnappedCueDoesNot() throws {
		let rig = try rig()
		rig.add(1, fade: 5, [(0, 1, 10)])
		rig.add(2, [(0, 1, 20)])
		rig.console.lists = [rig.look.identifier: rig.list]
		rig.console.play(rig.list, at: 0)
		
		#expect(rig.console.isMoving(rig.look.identifier))
		
		let other = Look.fresh(among: rig.looks, context: rig.context)
		
		#expect(!rig.console.isMoving(other.identifier))
		
		rig.console.play(rig.list, at: 1, snapping: true)
		
		#expect(!rig.console.isMoving(rig.look.identifier))
		#expect(CueList.milliseconds(1e300) == 3_600_000)
		#expect(CueList.milliseconds(.nan) == 0)
		#expect(CueList.milliseconds(-4) == 0)
	}
	
	@Test func theMarkStaysPutWhileTheSceneRunsOn() throws {
		let rig = try rig()
		rig.add(1, [(0, 1, 10)])
		let second = rig.add(2, [(0, 1, 20)])
		rig.add(3, [(0, 1, 30)])
		rig.console.play(rig.list, at: 1, snapping: true)
		rig.console.selection.build(rig.look.identifier)
		rig.console.keep(rig.look, among: rig.cues, fixtures: rig.fixtures, library: rig.library)
		rig.console.go(rig.list)
		
		let held = rig.look.cues(among: rig.cues)
		#expect(rig.console.marked(among: held).map { held[$0].identifier } == second.identifier)
	}
	
	@Test func addingCuesToANarrowedSceneKeepsItNarrowed() throws {
		let rig = try rig()
		rig.add(1, [(0, 2, 10), (0, 3, 10), (0, 4, 10)])
		rig.console.selection.build(rig.look.identifier)
		rig.console.keep(rig.look, among: rig.cues, fixtures: rig.fixtures, library: rig.library)
		let next = rig.recording(.cue(rig.look, after: nil))
		
		#expect(next.lights == [rig.fixtures[0].identifier])
		#expect(next.features == [.color])
		#expect(next.hint == "1 light")
	}
	
	@Test func resettingANewCueGoesBackToWhatTheBuilderChoseOnOpening() throws {
		let rig = try rig()
		rig.add(1, [(0, 2, 10), (0, 3, 10), (0, 4, 10)])
		rig.console.selection.build(rig.look.identifier)
		rig.console.keep(rig.look, among: rig.cues, fixtures: rig.fixtures, library: rig.library)
		let next = rig.recording(.cue(rig.look, after: nil))
		
		#expect(next.isDefault)
		
		next.label = "Storm"
		next.fade = 3
		next.delay = 1
		next.follow = 2
		next.features = [.dimmer]
		next.lights = Set(rig.fixtures.map(\.identifier))
		
		#expect(!next.isDefault)
		
		next.reset()
		
		#expect(next.isDefault)
		#expect(next.label.isEmpty)
		#expect(next.fade == 0)
		#expect(next.delay == 0)
		#expect(next.follow == nil)
		#expect(next.lights == [rig.fixtures[0].identifier])
		#expect(next.features == [.color])
		#expect(rig.recording(.cue(rig.look, after: nil)).isDefault)
	}
	
	@Test func aNewSceneResetsToAllLightsAndPicksAllWithoutLeavingTheDefault() throws {
		let rig = try rig()
		let fresh = Look.fresh(among: rig.looks, context: rig.context)
		rig.console.selection.build(fresh.identifier, isNew: true)
		rig.console.keep(fresh, among: rig.cues, fixtures: rig.fixtures, library: rig.library)
		let next = rig.recording(.cue(fresh, after: nil))
		
		next.lights = []
		
		#expect(!next.isDefault)
		
		next.lights = Set(rig.fixtures.map(\.identifier))
		
		#expect(next.isDefault)
		
		next.fade = 2
		next.reset()
		
		#expect(next.lights == Set(rig.fixtures.map(\.identifier)))
		#expect(next.features == Set(FeatureGroup.allCases))
		#expect(next.isDefault)
	}
	
	@Test func aSceneNeverEndsUpWithoutAName() throws {
		let rig = try rig()
		rig.look.name = "   "
		rig.look.settle(name: "Act One", among: rig.looks)
		
		#expect(rig.look.name == "Act One")
		
		rig.look.name = "  Storm  "
		rig.look.settle(name: "Act One", among: rig.looks)
		
		#expect(rig.look.name == "Storm")
		
		rig.look.name = ""
		rig.look.settle(name: " ", among: rig.looks)
		
		#expect(!rig.look.name.isEmpty)
		#expect(rig.looks.filter { $0.name == rig.look.name }.count == 1)
	}
	
	@Test func randomBuilderSessionsKeepEveryButtonHonest() async throws {
		var seed: UInt64 = 0x9E3779B97F4A7C15
		
		func roll(_ count: Int) -> Int {
			seed = seed &* 6364136223846793005 &+ 1442695040888963407
			return Int((seed >> 33) % UInt64(count))
		}
		
		let addresses = [1, 2, 3, 4, 5, 6, 7, 11, 12, 13, 14, 15, 16, 17, 21]
		let values: [UInt8] = [0, 50, 128, 255]
		
		for session in 0..<60 {
			let rig = try rig()
			let look = rig.look
			
			for index in 0...roll(3) {
				rig.add(Double(index + 1), [(0, 1, values[roll(4)]), (1, 2, values[roll(4)]), (2, 1, values[roll(4)])])
			}
			
			rig.console.selection.building = look.identifier
			rig.console.keep(look, among: rig.cues, fixtures: rig.fixtures, library: rig.library)
			var kept = rig.console.selection.kept
			
			for step in 0..<30 {
				try await Task.sleep(for: .milliseconds(1))
				let place = "session \(session) step \(step)"
				let held = look.cues(among: rig.cues)
				let marked = rig.console.marked(among: held).map { held[$0] }
				
				switch roll(10) {
				case 0, 1, 2: rig.console.set(values[roll(4)], at: DMXAddress(addresses[roll(addresses.count)])!)
				case 3: rig.console.selection.toggle(rig.fixtures[roll(3)])
				case 4:
					let recording = rig.recording(.cue(look, after: marked))
					recording.features = Set(FeatureGroup.allCases.filter { _ in roll(3) > 0 } + [.dimmer])
					recording.lights = Set(rig.fixtures.filter { _ in roll(3) > 0 }.map(\.identifier))
				case 5:
					let recording = rig.recording(.cue(look, after: marked))
					guard recording.isReady else { break }
					let stored = recording.levels
					recording.store(context: rig.context)
					let fresh = look.cues(among: rig.cues).first { $0.identifier == rig.console.selection.marked }
					#expect(fresh?.levels == stored, "\(place) stored something other than the stage")
				case 6:
					guard !held.isEmpty else { break }
					rig.console.selection.marked = held[roll(held.count)].identifier
				case 7:
					guard let marked else { break }
					let update = rig.recording(.into(marked))
					guard update.isReady else { break }
					update.store(context: rig.context)
					let after = rig.recording(.into(marked))
					#expect(!after.isReady, "\(place) Update stayed after updating")
					
					for (light, slots) in after.tracked.lights {
						let fixture = rig.fixtures.first { $0.identifier == light }!
						
						for (slot, value) in slots {
							#expect(rig.console.value(at: fixture.start.offset(by: slot - 1)!) == value, "\(place) cue differs from the stage after updating")
						}
					}
				case 8:
					guard let marked else { break }
					
					switch roll(3) {
					case 0:
						guard held.count > 1 else { break }
						rig.console.delete([marked], from: rig.list, context: rig.context)
					case 1:
						guard let from = held.firstIndex(where: { $0.identifier == marked.identifier }) else { break }
						let to = roll(held.count + 1)
						var expected = held.map(\.identifier)
						let moved = expected.remove(at: from)
						expected.insert(moved, at: to > from ? to - 1 : to)
						rig.console.move(IndexSet(integer: from), to: to, among: held, sortIndex: \.sortIndex)
						try? rig.context.save()
						#expect(look.cues(among: rig.cues).map(\.identifier) == expected, "\(place) a moved cue did not land where it was dropped")
					default:
						let show = rig.recording(.into(marked))
						guard !show.isOnStage else { break }
						show.show()
						#expect(rig.recording(.into(marked)).isOnStage, "\(place) Show left the stage different from the cue")
					}
					
					try? rig.context.save()
				default:
					guard let snapshot = kept else { break }
					
					if roll(2) == 0 {
						rig.console.discard(look, among: rig.cues, fixtures: rig.fixtures, context: rig.context)
						#expect(look.entry == snapshot.scene, "\(place) discard left the scene changed")
						#expect(look.cues(among: rig.cues).map(\.entry) == snapshot.cues, "\(place) discard left the cues changed")
						#expect(rig.console.playback.cue(of: look.identifier) == snapshot.playing, "\(place) discard left the scene on another cue")
					} else {
						rig.console.selection.building = nil
					}
					
					let stage = addresses.map { rig.console.value(at: DMXAddress($0)!) }
					rig.console.selection.building = look.identifier
					rig.console.keep(look, among: rig.cues, fixtures: rig.fixtures, library: rig.library)
					kept = rig.console.selection.kept
					#expect(!rig.console.hasChanged(look, among: rig.cues), "\(place) a fresh builder shows changes")
					#expect(addresses.map { rig.console.value(at: DMXAddress($0)!) } == stage, "\(place) opening the builder moved the stage")
					let reopened = look.cues(among: rig.cues)
					#expect(rig.console.marked(among: reopened).map { reopened[$0].identifier } == rig.console.playback.cue(of: look.identifier) ?? reopened.last?.identifier, "\(place) the builder did not mark the cue on stage")
				}
				
				let now = look.cues(among: rig.cues)
				guard let current = rig.console.marked(among: now).map({ now[$0] }) else { continue }
				let update = rig.recording(.into(current))
				let tracked = update.tracked
				var differs = false
				var shows = false
				
				for fixture in rig.fixtures {
					let owned = tracked.lights[fixture.identifier] ?? [:]
					
					for slot in 1...7 {
						guard let address = fixture.start.offset(by: slot - 1), addresses.contains(address.value) else { continue }
						
						if let value = owned[slot] {
							differs = differs || rig.console.value(at: address) != value
							shows = shows || rig.console.value(at: address) != value
						} else {
							differs = differs || rig.console.isChanged(address)
						}
					}
				}
				
				#expect(update.isOnStage == !shows, "\(place) Show is \(update.isOnStage ? "hidden" : "shown") while the stage \(shows ? "differs from" : "matches") the cue")
				#expect(update.isReady == differs, "\(place) Update is \(update.isReady ? "shown" : "hidden") while the stage \(differs ? "differs from" : "matches") the cue")
			}
		}
	}
	
	@Test func discardingPutsTheSceneAndItsCuesBackAsTheBuilderFoundThem() throws {
		let rig = try rig()
		let first = rig.add(1, [(0, 1, 10)])
		let second = rig.add(2, [(0, 1, 20)])
		rig.console.selection.building = rig.look.identifier
		rig.console.keep(rig.look, among: rig.cues, fixtures: rig.fixtures, library: rig.library)
		
		#expect(!rig.console.hasChanged(rig.look, among: rig.cues))
		
		rig.look.name = "Storm"
		rig.look.tint = .red
		rig.console.set(99, at: DMXAddress(1)!)
		rig.recording(.into(first)).store(context: rig.context)
		rig.recording(.cue(rig.look, after: first)).store(context: rig.context)
		rig.console.delete([second], from: rig.list, context: rig.context)
		try? rig.context.save()
		
		#expect(rig.console.hasChanged(rig.look, among: rig.cues))
		
		rig.console.discard(rig.look, among: rig.cues, fixtures: rig.fixtures, context: rig.context)
		
		let held = rig.look.cues(among: rig.cues)
		#expect(rig.look.name == "Play")
		#expect(rig.look.tint == .none)
		#expect(held.map(\.identifier) == [first.identifier, second.identifier])
		#expect(held.map { $0.levels.lights[rig.fixtures[0].identifier]?[1] } == [10, 20])
		#expect(rig.console.selection.building == nil)
		#expect(rig.console.playback.cue(of: rig.look.identifier) == nil)
	}
	
	@Test func discardingASceneTheBuilderStartedEmptyDeletesIt() throws {
		let rig = try rig()
		let fresh = Look.fresh(among: rig.looks, context: rig.context)
		rig.console.selection.build(fresh.identifier, isNew: true)
		rig.console.keep(fresh, among: rig.cues, fixtures: rig.fixtures, library: rig.library)
		
		#expect(!rig.console.hasChanged(fresh, among: rig.cues))
		
		fresh.name = "Renamed"
		
		#expect(!rig.console.hasChanged(fresh, among: rig.cues))
		
		rig.recording(.cue(fresh, after: nil)).store(context: rig.context)
		
		#expect(rig.console.hasChanged(fresh, among: rig.cues))
		#expect(rig.console.playback.cue(of: fresh.identifier) != nil)
		
		rig.console.discard(fresh, among: rig.cues, fixtures: rig.fixtures, context: rig.context)
		try? rig.context.save()
		
		#expect(rig.looks.count == 1)
		#expect(rig.cues.isEmpty)
		#expect(rig.console.playback.cue(of: fresh.identifier) == nil)
	}
	
	@Test func discardingPutsTheStageBackOnTheCueItWasOn() throws {
		let rig = try rig()
		let first = rig.add(1, [(0, 1, 10)])
		rig.add(2, [(0, 1, 20)])
		rig.console.play(rig.list, at: 0, snapping: true)
		rig.console.selection.building = rig.look.identifier
		rig.console.keep(rig.look, among: rig.cues, fixtures: rig.fixtures, library: rig.library)
		rig.recording(.cue(rig.look, after: nil)).store(context: rig.context)
		
		#expect(rig.console.playback.cue(of: rig.look.identifier) != first.identifier)
		
		rig.console.discard(rig.look, among: rig.cues, fixtures: rig.fixtures, context: rig.context)
		
		#expect(rig.console.playback.cue(of: rig.look.identifier) == first.identifier)
		#expect(rig.look.cues(among: rig.cues).count == 2)
	}
	
	@Test func aNewCueCanGoBetweenTwoOthers() throws {
		let rig = try rig()
		let first = rig.add(1, [(0, 1, 1)])
		rig.add(2, [(0, 1, 2)])
		rig.console.set(77, at: DMXAddress(2)!)
		let recording = rig.recording(.cue(rig.look, after: first))
		recording.label = "Storm rolls in"
		recording.features = [.color]
		recording.store(context: rig.context)
		
		let held = rig.look.cues(among: rig.cues)
		#expect(held.map(\.sortIndex) == [1, 1.5, 2])
		#expect(held[1].label == "Storm rolls in")
		#expect(held[1].levels.lights[rig.fixtures[0].identifier]?[2] == 77)
		#expect(held[0].label.isEmpty)
		#expect(rig.recording(.cue(rig.look, after: held[1])).number == 3)
		#expect(rig.recording(.cue(rig.look, after: nil)).number == 4)
	}
	
	@Test func aStoredCueIsOnStageWithoutMovingTheLights() throws {
		let rig = try rig()
		let first = rig.add(1, [(0, 1, 10)])
		rig.add(2, [(0, 1, 20)])
		rig.console.play(rig.list, at: 0, snapping: true)
		rig.console.set(55, at: DMXAddress(1)!)
		rig.recording(.cue(rig.look, after: first)).store(context: rig.context)
		
		let held = rig.look.cues(among: rig.cues)
		#expect(rig.console.playback.cue(of: rig.look.identifier) == held[1].identifier)
		#expect(rig.value(1) == 55)
		
		rig.console.go(rig.list)
		
		#expect(rig.console.playback.cue(of: rig.look.identifier) == held[2].identifier)
	}
	
	@Test func aSecondCueMakesTheTileStepThroughCuesUntilChosenOtherwise() throws {
		let rig = try rig()
		let first = rig.add(1, [(0, 1, 1)])
		rig.recording(.cue(rig.look, after: first)).store(context: rig.context)
		
		#expect(rig.look.tap == .next)
		#expect(rig.look.buttons == [.back, .toggle])
		
		rig.look.tap = .toggle
		rig.look.shows(.flash, true)
		rig.look.shows(.back, false)
		rig.recording(.cue(rig.look, after: nil)).store(context: rig.context)
		
		#expect(rig.look.tap == .toggle)
		#expect(rig.look.buttons == [.toggle, .flash])
	}
	
	@Test func storingIntoACueReplacesOnlyWhatWasChosen() throws {
		let rig = try rig()
		let cue = rig.add(1, [(0, 1, 255), (1, 1, 255)])
		rig.console.play(rig.list, at: 0, snapping: true)
		rig.console.set(9, at: DMXAddress(1)!)
		rig.console.selection.toggle(rig.fixtures[0])
		let recording = rig.recording(.into(cue))
		recording.features = [.dimmer]
		recording.store(context: rig.context)
		
		#expect(cue.levels.lights[rig.fixtures[0].identifier] == [1: 9])
		#expect(cue.levels.lights[rig.fixtures[1].identifier] == [1: 255])
	}
	
	@Test func aNewCueTakesItsTimingFromTheStoreAndAnUpdateLeavesItAlone() throws {
		let rig = try rig()
		let recording = rig.recording(.cue(rig.look, after: nil))
		recording.label = "Storm"
		recording.fade = 2
		recording.delay = 1
		recording.follow = 0.5
		recording.store(context: rig.context)
		
		let cue = rig.look.cues(among: rig.cues)[0]
		#expect(cue.delay == 1)
		#expect(cue.follow == 0.5)
		
		rig.console.set(40, at: DMXAddress(1)!)
		let update = rig.recording(.into(cue))
		update.store(context: rig.context)
		
		#expect(update.title == "Update Cue 1")
		#expect(cue.label == "Storm")
		#expect(cue.fade == 2)
		#expect(cue.levels.lights[rig.fixtures[0].identifier]?[1] == 40)
	}
	
	@Test func theBuilderKeepsTheAspectsChosenUntilAnotherSceneIsBuilt() throws {
		let rig = try rig()
		rig.console.selection.building = rig.look.identifier
		let recording = rig.recording(.cue(rig.look, after: nil))
		recording.features = [.dimmer]
		recording.store(context: rig.context)
		
		#expect(rig.recording(.cue(rig.look, after: nil)).features == [.dimmer])
		
		rig.console.selection.building = nil
		
		#expect(rig.recording(.cue(rig.look, after: nil)).features == Set(FeatureGroup.allCases))
	}
	
	@Test func theStoreSettingsStayWithoutStoringACue() throws {
		let rig = try rig()
		rig.console.selection.building = rig.look.identifier
		let recording = rig.recording(.cue(rig.look, after: nil))
		recording.features = [.position]
		recording.fade = 4
		recording.lights = [rig.fixtures[1].identifier]
		
		let next = rig.recording(.cue(rig.look, after: nil))
		#expect(rig.look.cues(among: rig.cues).isEmpty)
		#expect(next.features == [.position])
		#expect(next.fade == 4)
		#expect(next.lights == [rig.fixtures[1].identifier])
		#expect(next.hint == "1 light")
		
		rig.console.selection.toggle(rig.fixtures[0])
		
		#expect(rig.recording(.cue(rig.look, after: nil)).lights == [rig.fixtures[1].identifier])
	}
	
	@Test func updatingWaitsForATouchAndStoringInsertsAfterTheMarkedCueWithoutPlayingIt() throws {
		let rig = try rig()
		let first = rig.add(1, [(0, 1, 10)])
		rig.add(2, [(0, 1, 20)])
		rig.console.selection.building = rig.look.identifier
		
		#expect(!rig.console.isChanged(DMXAddress(1)!))
		
		rig.console.selection.marked = first.identifier
		rig.console.set(55, at: DMXAddress(1)!)
		
		#expect(rig.console.isChanged(DMXAddress(1)!))
		#expect(rig.console.playback.cue(of: rig.look.identifier) == nil)
		
		rig.recording(.cue(rig.look, after: first)).store(context: rig.context)
		
		let held = rig.look.cues(among: rig.cues)
		#expect(held.count == 3)
		#expect(rig.console.selection.marked == held[1].identifier)
		#expect(held[1].levels.lights[rig.fixtures[0].identifier]?[1] == 55)
	}
	
	@Test func intensityStoresTheDimmerBandOfALightWithoutADimmer() throws {
		let rig = try rig()
		let recording = rig.recording(.cue(rig.look, after: nil))
		recording.features = [.dimmer]
		
		#expect(recording.levels.lights[rig.fixtures[2].identifier]?.keys.sorted() == [1])
		#expect(recording.isReady)
		#expect(recording.levels.features(of: rig.fixtures[2].identifier, type: rig.library.type("head")) == [.dimmer])
	}
	
	@Test func allOffPutsBackEveryScene() async throws {
		let rig = try rig()
		let other = Look(name: "Other", sortIndex: 1)
		rig.context.insert(other)
		rig.add(1, [(0, 1, 100)])
		rig.add(1, to: other, [(1, 1, 200)])
		rig.console.toggle(rig.list)
		rig.console.toggle(rig.list(of: other))
		try await until { rig.value(1) == 100 && rig.value(11) == 200 }
		
		rig.console.stopAll()
		try await until { rig.value(1) == 0 && rig.value(11) == 0 }
		#expect(rig.console.playback.playing.isEmpty)
	}
	
	@Test func deletingTheCueOnStageLeavesTheSceneAbleToStartAgain() async throws {
		let rig = try rig()
		let first = rig.add(1, [(0, 1, 100)])
		rig.console.toggle(rig.list)
		try await until { rig.value(1) == 100 }
		rig.context.delete(first)
		try rig.context.save()
		let second = rig.add(2, [(0, 1, 50)])
		
		rig.console.toggle(rig.list)
		try await until { rig.console.playback.cue(of: rig.look.identifier) == second.identifier && rig.value(1) == 50 }
	}
	
	@Test func aChaseKeepsGoingRoundByItself() async throws {
		let rig = try rig()
		rig.look.loops = true
		
		for step in 1...3 {
			let cue = rig.add(Double(step), [(0, 1, UInt8(step * 10))])
			cue.follow = 0.05
		}
		
		try rig.context.save()
		rig.console.go(rig.list)
		var seen: [UInt8] = []
		
		try await until(within: 5) {
			if seen.last != rig.value(1) { seen.append(rig.value(1)) }
			return seen.count >= 8
		}
		
		#expect(Set(seen) == [10, 20, 30])
		#expect(rig.console.playback.cue(of: rig.look.identifier) != nil)
	}
	
	@Test func aChaseTooLongToSendAtOnceCarriesOnFromTheCues() async throws {
		let (console, list) = try wall()
		console.lists = [list.scene: list]
		#expect(list.program(from: 0).count < 6500)
		
		console.go(list)
		var seen: Set<UInt8> = []
		
		try await until(within: 5) {
			seen.insert(console.value(at: DMXAddress(512)!))
			return seen.count == 30
		}
	}
	
	@Test func aChaseWaitingForItsCuesCarriesOnOnceTheyArrive() async throws {
		let (console, list) = try wall()
		
		console.go(list)
		let stuck = try await settled(console, scene: list.scene)
		console.lists = [list.scene: list]
		
		#expect(try #require(list.index(of: stuck)) < 29)
		try await until { console.value(at: DMXAddress(512)!) == 30 }
	}
	
	@Test func aChaseContinuedWithoutALightLetsThatLightGo() async throws {
		let (console, list) = try wall()
		let (_, trimmed) = try wall(slots: 1...511)
		
		console.go(list)
		_ = try await settled(console, scene: list.scene)
		console.lists = [trimmed.scene: trimmed]
		
		try await until { console.value(at: DMXAddress(512)!) == 0 }
		#expect(console.value(at: DMXAddress(511)!) != 0)
	}
	
	@Test func aSceneTappedWhileTheControllerIsLostDoesNothing() async throws {
		let rig = try rig()
		rig.console.isMuted = false
		rig.add(1, [(0, 1, 255)])
		
		rig.console.toggle(rig.list)
		rig.console.flash(rig.list, isHeld: true)
		try await Task.sleep(for: .milliseconds(50))
		
		#expect(rig.value(1) == 0)
		#expect(rig.console.playback.playing.isEmpty)
	}
	
	@Test func aSixteenBitFadeThatLosesItsFineChannelEndsOnTheCoarseValue() async throws {
		let rig = try rig()
		rig.add(1, fade: 0.3, [(0, 5, 200), (0, 6, 0)])
		
		rig.console.go(rig.list)
		try await Task.sleep(for: .milliseconds(100))
		rig.library.setMade([FixtureType(id: "wash", model: "Wash", channels: [FixtureChannel(offset: 1, attribute: .dimmer), FixtureChannel(offset: 5, attribute: .pan, defaultValue: 128)]), Self.head])
		rig.console.applyPatch(rig.fixtures, library: rig.library)
		
		try await until { rig.value(5) == 200 }
	}
	
	@Test func aFlashOnASceneAlreadyOnLeavesItOn() async throws {
		let rig = try rig()
		rig.add(1, [(0, 1, 200)])
		rig.console.toggle(rig.list)
		try await until { rig.value(1) == 200 }
		
		rig.console.flash(rig.list, isHeld: true)
		rig.console.flash(rig.list, isHeld: false)
		
		try await Task.sleep(for: .milliseconds(50))
		#expect(rig.value(1) == 200)
		#expect(rig.console.playback.cue(of: rig.look.identifier) != nil)
	}
	
	@Test func deletingTheFirstCueOnStageMovesTheStageToTheNextOne() async throws {
		let rig = try rig()
		let first = rig.add(1, [(0, 1, 10)])
		let second = rig.add(2, [(0, 2, 20)])
		rig.add(3, [(0, 1, 30)])
		rig.console.play(rig.list, at: 0, snapping: true)
		try await until { rig.value(1) == 10 }
		
		rig.console.delete([first], from: rig.list, context: rig.context)
		
		#expect(rig.console.playback.cue(of: rig.look.identifier) == second.identifier)
		try await until { rig.value(1) == 0 && rig.value(2) == 20 }
	}
	
	@Test func deletingASceneThatIsOnPutsItsLightsBack() async throws {
		let rig = try rig()
		rig.console.set(40, at: DMXAddress(1)!)
		rig.add(1, [(0, 1, 255)])
		rig.console.toggle(rig.list)
		try await until { rig.value(1) == 255 }
		
		rig.console.remove(rig.look, with: rig.cues, context: rig.context)
		
		try await until { rig.value(1) == 40 }
		#expect(rig.console.playback.playing.isEmpty)
	}
	
	@Test func goingBackToACueBeforeALightIsSetShowsWhatAnotherSceneHoldsOnIt() async throws {
		let rig = try rig()
		let other = Look(name: "Other", sortIndex: 1)
		rig.context.insert(other)
		rig.add(1, to: other, [(0, 1, 200)])
		rig.add(1, [(0, 2, 50)])
		rig.add(2, [(0, 1, 100)])
		
		rig.console.toggle(rig.list(of: other))
		rig.console.go(rig.list)
		try await until { rig.value(1) == 200 && rig.value(2) == 50 }
		
		rig.console.go(rig.list)
		try await until { rig.value(1) == 100 }
		
		rig.console.back(rig.list)
		try await until { rig.value(1) == 200 }
	}
	
	@Test func turningASceneOffLeavesAnotherScenesFadeOnTheSameLightRunning() async throws {
		let rig = try rig()
		let other = Look(name: "Other", sortIndex: 1)
		rig.context.insert(other)
		rig.add(1, [(0, 1, 100)])
		rig.add(1, fade: 3, to: other, [(0, 1, 255)])
		
		rig.console.toggle(rig.list)
		try await until { rig.value(1) == 100 }
		rig.console.toggle(rig.list(of: other))
		try await until { (110...220).contains(rig.value(1)) }
		
		rig.console.toggle(rig.list)
		try await Task.sleep(for: .milliseconds(60))
		
		#expect(rig.value(1) < 250)
		try await until(within: 5) { rig.value(1) == 255 }
	}
	
	@Test func aLightTouchedWhileASceneHoldsItKeepsTheTouchWhenTheSceneGoesOff() async throws {
		let rig = try rig()
		rig.console.set(40, at: DMXAddress(1)!)
		rig.add(1, [(0, 1, 255)])
		
		rig.console.toggle(rig.list)
		try await until { rig.value(1) == 255 }
		rig.console.set(90, at: DMXAddress(1)!)
		
		rig.console.toggle(rig.list)
		try await Task.sleep(for: .milliseconds(60))
		
		#expect(rig.value(1) == 90)
	}
	
	@Test func aSceneStartedWhileAnotherFadesOutReturnsTheLightToWhereItWasBeforeBoth() async throws {
		let rig = try rig()
		let other = Look(name: "Other", sortIndex: 1)
		rig.context.insert(other)
		rig.add(1, fade: 3, [(0, 1, 255)])
		rig.add(1, to: other, [(0, 1, 100)])
		
		rig.console.play(rig.list, at: 0, snapping: true)
		try await until { rig.value(1) == 255 }
		rig.console.toggle(rig.list)
		try await until { (110...230).contains(rig.value(1)) }
		
		rig.console.toggle(rig.list(of: other))
		try await until { rig.value(1) == 100 }
		rig.console.toggle(rig.list(of: other))
		try await until { rig.value(1) == 0 }
	}
	
	@Test func deletingTheOnlyCueThatHeldALightPutsThatLightBack() async throws {
		let rig = try rig()
		rig.add(1, [(0, 1, 200)])
		let second = rig.add(2, [(1, 1, 150)])
		
		rig.console.play(rig.list, at: 1, snapping: true)
		try await until { rig.value(1) == 200 && rig.value(11) == 150 }
		
		rig.console.delete([second], from: rig.list, context: rig.context)
		try await until { rig.value(11) == 0 }
		#expect(rig.value(1) == 200)
	}
	
	@Test func aChainTheEngineCannotContinueStopsAskingAtItsLastCue() async throws {
		let (console, list) = try wall(renaming: 26)
		console.lists = [list.scene: list]
		
		console.go(list)
		let stuck = try await settled(console, scene: list.scene)
		
		#expect(try #require(list.index(of: stuck)) < 25)
		#expect(console.playback.playing.first?.wants == true)
	}
	
	@Test func storingCueAfterCueAtOneSpotKeepsTheirOrder() throws {
		let rig = try rig()
		var after = rig.add(1, [(0, 1, 1)])
		rig.add(2, [(0, 1, 2)])
		
		for step in 0..<60 {
			rig.console.set(UInt8(step + 3), at: DMXAddress(1)!)
			rig.recording(.cue(rig.look, after: after)).store(context: rig.context)
			after = try #require(rig.look.cues(among: rig.cues).first { $0.levels.lights[rig.fixtures[0].identifier]?[1] == UInt8(step + 3) })
		}
		
		let held = rig.look.cues(among: rig.cues)
		#expect(held.compactMap { $0.levels.lights[rig.fixtures[0].identifier]?[1] } == [1] + (3...62).map(UInt8.init) + [2])
		#expect(Set(held.map(\.sortIndex)).count == held.count)
		#expect(held.allSatisfy { ($0.sortIndex * 256).rounded() == $0.sortIndex * 256 })
	}
}
