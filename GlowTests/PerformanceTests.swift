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
		
		#expect(console.span == Universe.minimumSlots)
	}
	
	@Test func theSpanNeverReachesTheWholeUniverseForASmallRig() {
		let (console, _, _) = rig(30)
		
		#expect(console.span == 240)
		#expect(console.span < Universe.channelCount / 2)
	}
	
	@Test func syncingCuesNeverEncodesFixtureDefinitions() async {
		let show = Self.crowded()
		let scoped = await ShowLibrary.snapshot(of: show, folders: [.cues])
		
		#expect(scoped.keys.allSatisfy { $0.hasPrefix("cues/") })
		#expect(scoped.count == show.cues.count)
	}
	
	@Test func planningTheLastOfFortyCuesFitsInAFrame() {
		let (_, fixtures, library) = rig(60)
		let look = Look(name: "Look", sortIndex: 0)
		var cues: [Cue] = []
		
		for index in 0..<40 {
			var levels = Levels()
			
			for fixture in fixtures {
				levels.set(UInt8(index), slot: 1, of: fixture.identifier)
				levels.set(128, slot: 8, of: fixture.identifier)
			}
			
			cues.append(Cue(lookID: look.identifier, sortIndex: Double(index), fade: 0, levels: levels))
		}
		
		let clock = ContinuousClock()
		var best = Duration.seconds(60)
		var ramps: [Ramp] = []
		
		for _ in 0..<5 {
			best = min(best, clock.measure { ramps = CueList(look, cues: cues, fixtures: fixtures, library: library).ramps(at: 39, holding: [:]) })
		}
		
		#expect(best < .milliseconds(16))
		#expect(ramps.count == 120)
		#expect(ramps.contains { $0.target == 39 })
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
			var levels = Levels()
			
			for light in show.lights {
				for slot in 1...32 {
					levels.set(UInt8((index + slot) % 256), slot: slot, of: light.identifier)
				}
			}
			
			show.scenes.append(ShowContents.Scene(identifier: Identifier.fresh(), name: "Scene \(index)", sortIndex: Double(index)))
			show.cues.append(ShowContents.Cue(identifier: Identifier.fresh(), scene: show.scenes[index].identifier, sortIndex: 1, levels: levels.data))
		}
		
		return show
	}
}
