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
		console.applyPatch(fixtures, library: library)
		return Rig(console: console, library: library, container: container, fixtures: fixtures, look: look)
	}
	
	private func wall(renaming odd: Int? = nil) throws -> (Console, CueList) {
		let library = FixtureLibrary(builtIn: [])
		library.setMade([FixtureType(id: "wall", model: "Wall", channels: (1...512).map { FixtureChannel(offset: $0, attribute: .red) })])
		let container = try ModelContainer(for: Fixture.self, FixtureGroup.self, StoredFixtureType.self, Look.self, Cue.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
		let wall = Fixture(typeID: "wall", name: "Wall", address: DMXAddress(1)!, sortIndex: 0)
		let look = Look(name: "Chase", sortIndex: 0)
		container.mainContext.insert(wall)
		container.mainContext.insert(look)
		
		for step in 1...30 {
			var levels = Levels()
			
			for slot in 1...512 {
				levels.set(UInt8(step), slot: slot, of: wall.identifier)
			}
			
			let cue = Cue(lookID: look.identifier, sortIndex: Double(step), fade: 0, levels: levels)
			cue.follow = 0.03
			if step == odd { cue.identifier = String(repeating: "y", count: 60) }
			container.mainContext.insert(cue)
		}
		
		try container.mainContext.save()
		let console = Console()
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
	
	@Test func afterTheLastCueTheNextTapStartsAgainAtTheFirst() async throws {
		let rig = try rig()
		let first = rig.add(1, [(0, 1, 10)])
		let second = rig.add(2, [(0, 1, 20)])
		
		rig.console.go(rig.list)
		rig.console.go(rig.list)
		try await until { rig.console.playback.cue(of: rig.look.identifier) == second.identifier }
		
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
	
	@Test func aSelectionStoresOnlyItsLightsAndNothingSelectedStoresAll() throws {
		let rig = try rig()
		rig.console.set(120, at: DMXAddress(11)!)
		rig.console.selection.toggle(rig.fixtures[0])
		let recording = rig.recording(.cue(rig.look, after: nil))
		
		#expect(recording.lights == [rig.fixtures[0].identifier])
		#expect(recording.hint == "1 light")
		
		rig.console.selection.clear()
		
		#expect(rig.recording(.cue(rig.look, after: nil)).lights == Set(rig.fixtures.map(\.identifier)))
	}
	
	@Test func deletingTheLiveCueMovesTheStageToTheOneBefore() throws {
		let rig = try rig()
		rig.add(1, [(0, 1, 10)])
		let second = rig.add(2, [(0, 1, 20)])
		rig.console.play(rig.list, at: 1, snapping: true)
		rig.console.delete(second, from: rig.list, context: rig.context)
		
		let held = rig.look.cues(among: rig.cues)
		#expect(held.count == 1)
		#expect(rig.console.playback.cue(of: rig.look.identifier) == held[0].identifier)
		
		rig.console.delete(held[0], from: rig.list, context: rig.context)
		
		#expect(rig.console.playback.cue(of: rig.look.identifier) == nil)
	}
	
	@Test func updateStoresTheSelectedLightIntoTheCue() throws {
		let rig = try rig()
		let cue = rig.add(1, [(0, 1, 200)])
		rig.console.set(70, at: DMXAddress(11)!)
		rig.console.release(11...11)
		rig.console.selection.toggle(rig.fixtures[1])
		
		#expect(rig.recording(.cue(rig.look, after: cue)).hint == "1 light")
		
		rig.recording(.into(cue)).store(context: rig.context)
		
		#expect(cue.levels.lights[rig.fixtures[1].identifier]?[1] == 70)
		#expect(cue.levels.lights[rig.fixtures[0].identifier]?[1] == 200)
		#expect(!rig.console.selection.isEmpty)
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
		#expect(held.map(\.sortIndex) == [1, 1.125, 2])
		#expect(held[1].title(at: 1) == "Storm rolls in")
		#expect(held[1].levels.lights[rig.fixtures[0].identifier]?[2] == 77)
		#expect(held[0].title(at: 0) == "Cue 1")
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
		rig.console.set(9, at: DMXAddress(1)!)
		rig.console.selection.toggle(rig.fixtures[0])
		let recording = rig.recording(.into(cue))
		recording.features = [.dimmer]
		recording.store(context: rig.context)
		
		#expect(cue.levels.lights[rig.fixtures[0].identifier] == [1: 9])
		#expect(cue.levels.lights[rig.fixtures[1].identifier] == [1: 255])
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
		
		rig.console.delete(first, from: rig.list, context: rig.context)
		
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
		
		rig.console.delete(second, from: rig.list, context: rig.context)
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
