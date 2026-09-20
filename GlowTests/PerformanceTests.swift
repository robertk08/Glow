import Foundation
import Testing

@testable import Glow

@MainActor
struct PerformanceTests {
	private func rig(_ count: Int) -> (Console, [Fixture], FixtureLibrary) {
		let library = FixtureLibrary(builtIn: [])
		let type = FixtureType(id: "eight", model: "Eight", channels: [FixtureChannel(offset: 1, attribute: .dimmer), FixtureChannel(offset: 8, attribute: .red)])
		library.setMade([type])
		
		let fixtures = (0..<count).map { Fixture(typeID: "eight", name: "Light \($0)", address: DMXAddress($0 * 8 + 1)!, sortIndex: Double($0)) }
		let console = Console()
		console.applyPatch(fixtures, library: library)
		return (console, fixtures, library)
	}
	
	@Test func theSpanCoversOnlyThePatchedChannels() {
		let (console, _, _) = rig(15)
		
		#expect(console.span == 120)
	}
	
	@Test func anEmptyPatchStillHoldsTheMinimumSpan() {
		let console = Console()
		console.applyPatch([], library: FixtureLibrary(builtIn: []))
		
		#expect(console.span == DmxBus.minimumSlots)
	}
	
	@Test func theSpanNeverReachesTheWholeUniverseForASmallRig() {
		let (console, _, _) = rig(30)
		
		#expect(console.span == 240)
		#expect(console.span < DmxBus.universeSlots / 2)
	}
	
	@Test func syncingScenesNeverEncodesFixtureDefinitions() async {
		let show = Self.crowded()
		let scoped = await ShowLibrary.snapshot(of: show, folders: [.scenes])
		
		#expect(scoped.keys.allSatisfy { $0.hasPrefix("scenes/") })
		#expect(scoped.count == show.scenes.count)
	}
	
	@Test func aScopedSnapshotIsFarCheaperThanAFullOne() async {
		let show = Self.crowded()
		var full = Duration.seconds(60)
		var scoped = Duration.seconds(60)
		
		for _ in 0..<5 {
			let clock = ContinuousClock()
			full = min(full, await clock.measure { _ = await ShowLibrary.snapshot(of: show) })
			scoped = min(scoped, await clock.measure { _ = await ShowLibrary.snapshot(of: show, folders: [.scenes]) })
		}
		
		#expect(scoped < full / 1.25)
		#expect(scoped < .milliseconds(50))
	}
	
	@Test func recallingASceneStaysWellUnderAFrame() {
		let (console, fixtures, library) = rig(60)
		var levels: [String: Data] = [:]
		
		for fixture in fixtures {
			levels[fixture.identifier] = Data(repeating: 128, count: 8)
		}
		
		let look = Look(name: "Look", sortIndex: 0, levels: levels)
		let clock = ContinuousClock()
		var best = Duration.seconds(60)
		
		for _ in 0..<5 {
			best = min(best, clock.measure { console.recall(look, among: fixtures) })
		}
		
		#expect(best < .milliseconds(10))
		#expect(console.universe[DMXAddress(1)!] == 128)
		#expect(library.types.count == 1)
	}
	
	@Test func aFullSnapshotOfACrowdedShowStaysUnderAFrame() async {
		let show = Self.crowded()
		let clock = ContinuousClock()
		var best = Duration.seconds(60)
		
		for _ in 0..<5 {
			best = min(best, await clock.measure { _ = await ShowLibrary.snapshot(of: show) })
		}
		
		#expect(best < .milliseconds(50))
	}
	
	private static func crowded() -> ShowContents {
		var show = ShowContents()
		let library = FixtureLibrary()
		show.made = library.builtIn
		
		for index in 0..<60 {
			show.lights.append(ShowContents.Light(identifier: Identifier.fresh(), typeID: "eight", name: "Light \(index)", address: index * 8 + 1, sortIndex: Double(index)))
		}
		
		for index in 0..<40 {
			var levels: [String: Data] = [:]
			
			for light in show.lights {
				levels[light.identifier] = Data(repeating: UInt8(index % 256), count: 32)
			}
			
			show.scenes.append(ShowContents.Scene(identifier: Identifier.fresh(), name: "Scene \(index)", sortIndex: Double(index), levels: levels))
		}
		
		return show
	}
}
