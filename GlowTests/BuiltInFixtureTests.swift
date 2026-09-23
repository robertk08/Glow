import Foundation
import Testing

@testable import Glow

@MainActor
struct BuiltInFixtureTests {
	private let library = FixtureLibrary()
	
	@Test func everyBundledDefinitionLoads() {
		#expect(library.builtIn.count == 4)
		#expect(Set(library.builtIn.map(\.id)).count == library.builtIn.count)
		#expect(Set(library.types.map(\.id)).count == library.types.count)
	}
	
	@Test func everyModeCoversAContiguousBlockOfAddresses() {
		for mode in library.types {
			let slots = mode.channels.flatMap(\.offsets).sorted()
			#expect(slots == Array(1...slots.count), "\(mode.id) has gaps or overlaps: \(slots)")
		}
	}
	
	@Test func everyModeOpensWhiteWhenTheDimmerComesUp() {
		for mode in library.types where mode.dims && mode.mixesColor && mode.mixing == .additive {
			let console = Console()
			let programmer = Programmer(type: mode, start: DMXAddress(1)!, console: console)
			programmer.applyDefaults()
			
			#expect(programmer.brightness == 0, "\(mode.id) should start off")
			programmer.brightness = 1
			#expect(programmer.brightness > 0.99, "\(mode.id) should reach full")
			#expect(programmer.light.red > 0.9 && programmer.light.green > 0.9 && programmer.light.blue > 0.9, "\(mode.id) should open white")
		}
	}
	
	@Test func raisingTheDimmerLeavesColourUnsetWhereThereIsARealDimmer() {
		for mode in library.types where mode.channel(.dimmer) != nil && mode.mixesColor {
			let console = Console()
			let programmer = Programmer(type: mode, start: DMXAddress(1)!, console: console)
			programmer.applyDefaults()
			programmer.brightness = 1
			
			#expect(!programmer.isActive(.color), "\(mode.id) stamped colour when the dimmer came up")
		}
	}
	
	@Test func theFourFixturesAreAllHere() {
		#expect(library.type("cameo-f2-fc-16ch")?.channelCount == 16)
		#expect(library.type("stairville-bsw350-32ch")?.channelCount == 32)
		#expect(library.type("stairville-hl-x180-8ch")?.channelCount == 8)
		#expect(library.type("mini-moving-head-14ch")?.channelCount == 14)
	}
	
	@Test func theMovingHeadsKnowTheirTravel() {
		#expect(library.type("stairville-bsw350-32ch")?.panDegrees == 540)
		#expect(library.type("stairville-bsw350-32ch")?.tiltDegrees == 270)
		#expect(library.type("mini-moving-head-14ch")?.panDegrees == 540)
		#expect(library.type("mini-moving-head-14ch")?.invertsPan == true)
	}
	
	@Test func theBigHeadCarriesItsWheelsAndItsResets() {
		guard let mode = library.type("stairville-bsw350-32ch") else {
			Issue.record("missing the 32 channel mode")
			return
		}
		
		#expect(mode.channelCount == 32)
		#expect(mode.mixing == .subtractive)
		#expect(mode.channel(.gobo)?.functions.contains { !$0.sets.isEmpty } == true)
		#expect(mode.channel(.gobo2)?.functions.flatMap(\.sets).count == 23)
		#expect(mode.channel(.colorWheel)?.functions.flatMap(\.sets).count == 14)
		#expect(mode.channel(.cri) != nil)
		#expect(mode.channel(.positionMacro) != nil)
		#expect(mode.channel(.dimmerCurve) != nil)
		#expect(mode.channel(.zoom)?.functions.first?.unit == .degrees)
		#expect(mode.channel(.control)?.functions.filter(\.requiresConfirmation).count == 16)
	}
	
	@Test func theFresnelCarriesItsFilterLibrary() {
		guard let mode = library.type("cameo-f2-fc-16ch") else {
			Issue.record("missing the 16 channel mode")
			return
		}
		
		#expect(mode.channelCount == 16)
		#expect(mode.channel(.tint) != nil)
		#expect(mode.channel(.colorFade) != nil)
		#expect(mode.channel(.colorMacro)?.functions.flatMap(\.sets).count == 57)
		#expect(mode.channel(.colorTemperature)?.functions.count == 14)
		#expect(mode.channel(.red)?.isWide == true)
	}
	
	@Test func theFloodKnowsWhichChannelsItsColourDependsOn() {
		guard let mode = library.type("stairville-hl-x180-8ch") else {
			Issue.record("missing the 8 channel mode")
			return
		}
		
		#expect(mode.channel(.red)?.enabledBy?.offset == 5)
		#expect(mode.channel(.red)?.enabledBy?.contains(10) == true)
		#expect(mode.channel(.red)?.enabledBy?.contains(200) == false)
	}
	
	@Test func theSmallHeadDimsThroughItsShutter() {
		guard let mode = library.type("mini-moving-head-14ch") else {
			Issue.record("missing the 14 channel mode")
			return
		}
		
		guard case let .band(_, from, to, open) = mode.dimming else {
			Issue.record("expected a dim band")
			return
		}
		
		#expect(from == 8)
		#expect(to == 134)
		#expect(open == 240)
	}
	
	@Test func theFresnelBalancesWhiteAndReadsItBack() {
		guard let mode = library.type("cameo-f2-fc-16ch") else {
			Issue.record("missing the 16 channel mode")
			return
		}
		
		let console = Console()
		let programmer = Programmer(type: mode, start: DMXAddress(1)!, console: console)
		programmer.applyDefaults()
		
		#expect(programmer.balancesWhite)
		#expect(programmer.mixesColor)
		
		programmer.apply(kelvin: 3200)
		#expect(abs(programmer.kelvin - 3200) <= 100)
		#expect(programmer.isActive(.color))
		
		programmer.release(.color)
		#expect(!programmer.isActive(.color))
	}
	
	@Test func everyFilterPresetInTheFresnelHasASwatch() {
		guard let macro = library.type("cameo-f2-fc-16ch")?.channel(.colorMacro) else {
			Issue.record("missing the color preset channel")
			return
		}
		
		let filters = macro.functions.first { $0.from == 6 }.map(\.sets) ?? []
		
		#expect(filters.count == 49)
		#expect(filters.allSatisfy { !$0.swatch.isEmpty })
		#expect(macro.functions.first?.purpose == .release)
	}
	
	@Test func aStrobeReadsInHertzWhereTheManualGivesOne() {
		guard let mode = library.type("cameo-f2-fc-16ch"), let shutter = mode.channel(.shutter) else {
			Issue.record("missing the shutter")
			return
		}
		
		let console = Console()
		let programmer = Programmer(type: mode, start: DMXAddress(1)!, console: console)
		programmer.applyDefaults()
		
		#expect(programmer.strobeHertz == nil)
		programmer.set(250, of: shutter)
		#expect(programmer.strobeHertz.map { abs($0 - 20) < 0.1 } == true)
	}
	
	@Test func aHandMadeFixtureIsNoLessCapableThanABuiltInOne() throws {
		guard let builtIn = library.type("stairville-bsw350-32ch") else {
			Issue.record("missing the head")
			return
		}
		
		var mine = builtIn
		mine.id = "made-by-hand"
		let copy = try JSONDecoder().decode(FixtureType.self, from: JSONEncoder().encode(mine))
		
		let empty = FixtureLibrary(builtIn: [])
		empty.setMade([copy])
		
		guard let ours = empty.type("made-by-hand") else {
			Issue.record("a made fixture has to resolve on its own")
			return
		}
		
		#expect(ours.channels == builtIn.channels)
		#expect(ours.dimming == builtIn.dimming)
		#expect(ours.mixing == builtIn.mixing)
		#expect(ours.defaults == builtIn.defaults)
	}
	
	@Test func theAppWorksWithNoBuiltInDefinitionsAtAll() {
		let empty = FixtureLibrary(builtIn: [])
		let console = Console()
		
		#expect(empty.types.isEmpty)
		
		let mine = FixtureType(id: "mine", model: "Mine", channels: [
			FixtureChannel(offset: 1, attribute: .dimmer),
			FixtureChannel(offset: 2, attribute: .red),
			FixtureChannel(offset: 3, attribute: .green),
			FixtureChannel(offset: 4, attribute: .blue, defaultValue: 255),
		])
		empty.setMade([mine])
		
		guard let mode = empty.type("mine") else {
			Issue.record("a made fixture has to be patchable on its own")
			return
		}
		
		let programmer = Programmer(type: mode, start: DMXAddress(1)!, console: console)
		programmer.applyDefaults()
		programmer.brightness = 1
		
		#expect(programmer.isActive(.dimmer))
		#expect(!programmer.isActive(.color))
		#expect(console.value(at: DMXAddress(1)!) == 255)
	}
	
	@Test func theWhiteEngineReadsAsOneKelvinScale() {
		guard let mode = library.type("cameo-f2-fc-16ch"), let white = mode.channel(.colorTemperature) else {
			Issue.record("the F2 drives its whites on their own channel")
			return
		}
		
		let console = Console()
		let programmer = Programmer(type: mode, start: DMXAddress(1)!, console: console)
		programmer.applyDefaults()
		
		guard let scale = programmer.scale(of: white) else {
			Issue.record("the whites run from end to end, so they belong on one slider")
			return
		}
		
		#expect(scale.unit == .kelvin)
		#expect(scale.from == 6 && scale.to == 255)
		#expect(programmer.stops(of: white).map(\.label) == ["Off", "2000 K", "2700 K", "3200 K", "4000 K", "5600 K", "6500 K", "10000 K"])
		#expect(programmer.stops(of: white).map(\.value) == [2, 6, 47, 88, 129, 170, 211, 253])
		
		for value in scale.from...scale.to {
			programmer.set(value, of: white)
			#expect(programmer.physical(of: white) != nil, "\(value) should read as a temperature")
		}
	}
}
