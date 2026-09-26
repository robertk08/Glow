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
		var looks: [Look] { (try? context.fetch(FetchDescriptor<Look>())) ?? [] }
		var list: CueList { CueList(look, cues: cues, fixtures: fixtures, library: library) }
		
		func value(_ address: Int) -> UInt8 {
			console.value(at: DMXAddress(address)!)
		}
		
		@discardableResult func add(_ number: Int, fade: Double = 0, trigger: Trigger = .go, wait: Double = 0, _ values: [(light: Int, slot: Int, value: UInt8)]) -> Cue {
			var levels = Levels()
			
			for value in values {
				levels.set(value.value, slot: value.slot, of: fixtures[value.light].identifier)
			}
			
			let cue = Cue(lookID: look.identifier, number: number, fade: fade, levels: levels)
			cue.trigger = trigger
			cue.wait = wait
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
	
	private func until(within seconds: Double = 3, _ condition: () -> Bool) async throws {
		let start = Date()
		
		while Date().timeIntervalSince(start) < seconds {
			if condition() { return }
			try await Task.sleep(for: .milliseconds(5))
		}
		
		#expect(condition(), "timed out")
	}
	
	@Test func goRunsTheCuesInTurnAndValuesTrackThrough() async throws {
		let rig = try rig()
		let first = rig.add(1000, [(0, 1, 255), (0, 2, 255)])
		let second = rig.add(2000, [(0, 2, 0)])
		
		rig.console.go(rig.list)
		try await until { rig.console.activeCue == first.identifier && rig.value(2) == 255 }
		
		rig.console.go(rig.list)
		try await until { rig.console.activeCue == second.identifier && rig.value(2) == 0 }
		#expect(rig.value(1) == 255)
	}
	
	@Test func backPutsBackWhatALaterCueChanged() async throws {
		let rig = try rig()
		let first = rig.add(1000, [(0, 1, 255)])
		rig.add(2000, [(1, 1, 200), (0, 5, 10)])
		
		rig.console.go(rig.list)
		try await until { rig.value(1) == 255 }
		rig.console.go(rig.list)
		try await until { rig.value(11) == 200 }
		
		rig.console.back(rig.list)
		try await until { rig.console.activeCue == first.identifier && rig.value(11) == 0 }
		#expect(rig.value(1) == 255)
		#expect(rig.value(5) == 128)
	}
	
	@Test func aFadeGlidesWhileDiscreteChannelsSnap() async throws {
		let rig = try rig()
		rig.add(1000, [(0, 1, 0), (0, 7, 0)])
		rig.add(2000, fade: 1, [(0, 1, 200), (0, 7, 60)])
		
		rig.console.play(rig.list, at: 0)
		try await until { rig.console.activeCue != nil && !rig.console.isRunning }
		rig.console.play(rig.list, at: 1)
		var between: [(dimmer: UInt8, gobo: UInt8)] = []
		
		while rig.console.isRunning {
			if (1...199).contains(rig.value(1)) { between.append((rig.value(1), rig.value(7))) }
			try await Task.sleep(for: .milliseconds(5))
		}
		
		#expect(!between.isEmpty)
		#expect(between.allSatisfy { $0.gobo == 60 })
		#expect(rig.value(1) == 200)
	}
	
	@Test func aSixteenBitChannelFadesAsOneValue() async throws {
		let rig = try rig()
		rig.add(1000, [(0, 5, 0), (0, 6, 0)])
		rig.add(2000, fade: 1, [(0, 5, 255), (0, 6, 255)])
		
		rig.console.play(rig.list, at: 0)
		try await until { rig.value(5) == 0 && !rig.console.isRunning }
		rig.console.play(rig.list, at: 1)
		var coarse: Set<UInt8> = []
		
		while rig.console.isRunning {
			coarse.insert(rig.value(5))
			try await Task.sleep(for: .milliseconds(5))
		}
		
		#expect(coarse.contains { (40...230).contains($0) })
		#expect(rig.value(5) == 255 && rig.value(6) == 255)
	}
	
	@Test func aBandDimmerFadesInsideItsBandRatherThanThroughTheStrobe() async throws {
		let rig = try rig()
		rig.add(1000, [(2, 1, 0)])
		rig.add(2000, fade: 0.6, [(2, 1, 240)])
		
		rig.console.play(rig.list, at: 0)
		try await until { !rig.console.isRunning }
		rig.console.play(rig.list, at: 1)
		var seen: Set<UInt8> = []
		
		while rig.console.isRunning {
			seen.insert(rig.value(21))
			try await Task.sleep(for: .milliseconds(5))
		}
		
		#expect(rig.value(21) == 240)
		#expect(seen.contains { (8...134).contains($0) })
		#expect(!seen.contains { (135...239).contains($0) })
	}
	
	@Test func theProgrammerTakesAChannelOverMidFade() async throws {
		let rig = try rig()
		rig.add(1000, fade: 0.4, [(0, 1, 200), (0, 2, 180)])
		
		rig.console.go(rig.list)
		try await Task.sleep(for: .milliseconds(100))
		rig.console.set(50, at: DMXAddress(1)!)
		try await until { !rig.console.isRunning }
		
		#expect(rig.value(1) == 50)
		#expect(rig.value(2) == 180)
	}
	
	@Test func aFollowCueAndATimedCueRunByThemselves() async throws {
		let rig = try rig()
		rig.add(1000, [(0, 1, 10)])
		rig.add(2000, fade: 0.1, trigger: .follow, [(0, 1, 20)])
		let timed = rig.add(3000, trigger: .wait, wait: 0.2, [(0, 1, 30)])
		let manual = rig.add(4000, [(0, 1, 40)])
		
		let started = Date()
		rig.console.go(rig.list)
		try await until { rig.console.activeCue == timed.identifier && rig.value(1) == 30 }
		
		#expect(Date().timeIntervalSince(started) >= 0.2)
		try await until { !rig.console.isRunning }
		#expect(rig.console.activeCue != manual.identifier)
	}
	
	@Test func aLoopingListComesBackAroundUntilStopped() async throws {
		let rig = try rig()
		rig.look.loops = true
		let first = rig.add(1000, trigger: .wait, wait: 0.05, [(0, 2, 255)])
		let second = rig.add(2000, trigger: .wait, wait: 0.05, [(0, 2, 0)])
		
		rig.console.go(rig.list)
		try await until { rig.console.activeCue == second.identifier }
		try await until { rig.console.activeCue == first.identifier }
		
		rig.console.stop()
		#expect(!rig.console.isRunning)
	}
	
	@Test func aSceneOfOneCueComesBackOnEveryGo() async throws {
		let rig = try rig()
		rig.add(1000, [(0, 1, 255)])
		
		rig.console.go(rig.list)
		try await until { rig.value(1) == 255 }
		rig.console.set(3, at: DMXAddress(1)!)
		rig.console.go(rig.list)
		try await until { rig.value(1) == 255 }
	}
	
	@Test func storingChangesKeepsOnlyWhatWasTouchedAndClearsTheMarks() throws {
		let rig = try rig()
		rig.console.set(255, at: DMXAddress(1)!)
		rig.console.set(90, at: DMXAddress(13)!)
		let recording = rig.recording(.scene)
		recording.keepsEverything = false
		
		#expect(recording.changed == [rig.fixtures[0].identifier, rig.fixtures[1].identifier])
		#expect(recording.levels.lights == [rig.fixtures[0].identifier: [1: 255], rig.fixtures[1].identifier: [3: 90]])
		
		recording.store(context: rig.context)
		
		#expect(rig.looks.count == 2)
		#expect(rig.cues.count == 1)
		#expect(rig.console.activeCue == rig.cues.first?.identifier)
		#expect(!rig.console.isActive(DMXAddress(1)!))
		#expect(!rig.console.isActive(DMXAddress(13)!))
	}
	
	@Test func storingEverythingTakesEveryChannelOfTheChosenLightsItsFeaturesAllow() throws {
		let rig = try rig()
		let recording = rig.recording(.scene)
		recording.lights = [rig.fixtures[0].identifier]
		
		#expect(recording.levels.slotCount == 7)
		
		recording.toggle(.position)
		
		#expect(recording.levels.lights[rig.fixtures[0].identifier]?.keys.sorted() == [1, 2, 3, 4, 7])
	}
	
	@Test func aNewCueLandsAfterTheOneOnStage() throws {
		let rig = try rig()
		let first = rig.add(1000, [(0, 1, 1)])
		rig.add(2000, [(0, 1, 2)])
		rig.console.arrive(at: first.identifier)
		rig.console.set(77, at: DMXAddress(2)!)
		
		rig.recording(.cue(rig.look)).store(context: rig.context)
		
		#expect(rig.look.cues(among: rig.cues).map(\.number) == [1000, 1500, 2000])
		#expect(rig.look.cues(among: rig.cues)[1].levels.lights == [rig.fixtures[0].identifier: [2: 77]])
	}
	
	@Test func storingIntoACueMergesUnlessItReplaces() throws {
		let rig = try rig()
		let cue = rig.add(1000, [(0, 1, 255), (1, 1, 255)])
		rig.console.set(9, at: DMXAddress(2)!)
		rig.recording(.into(cue)).store(context: rig.context)
		
		#expect(cue.levels.lights[rig.fixtures[0].identifier] == [1: 255, 2: 9])
		#expect(cue.levels.lights[rig.fixtures[1].identifier] == [1: 255])
		
		rig.console.set(4, at: DMXAddress(3)!)
		let replacing = rig.recording(.into(cue))
		replacing.replaces = true
		replacing.store(context: rig.context)
		
		#expect(cue.levels.lights == [rig.fixtures[0].identifier: [3: 4]])
	}
}
