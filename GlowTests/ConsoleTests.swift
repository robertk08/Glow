import Testing

@testable import Glow

struct ConsoleTests {
	@Test func anAddressStaysInsideTheUniverse() {
		#expect(DMXAddress(0) == nil)
		#expect(DMXAddress(513) == nil)
		#expect(DMXAddress(clamping: 900).value == 512)
		#expect(DMXAddress(clamping: -4).value == 1)
		#expect(DMXAddress(1)?.offset(by: 511)?.value == 512)
		#expect(DMXAddress(1)?.offset(by: 512) == nil)
	}
	
	@Test func writingPastTheEndOfTheUniverseStops() {
		var universe = Universe()
		universe.set([1, 2, 3], at: DMXAddress(511)!)
		
		#expect(universe[DMXAddress(511)!] == 1)
		#expect(universe[DMXAddress(512)!] == 2)
	}
	
	@MainActor @Test func masterScalesALinearDimmer() {
		let dimmer = Console.Dimmer(address: DMXAddress(1)!, kind: .linear)
		
		#expect(dimmer.scale(200, by: 1) == 200)
		#expect(dimmer.scale(200, by: 0.5) == 100)
		#expect(dimmer.scale(200, by: 0) == 0)
	}
	
	@MainActor @Test func masterScalesInsideADimBandOnly() {
		let dimmer = Console.Dimmer(address: DMXAddress(1)!, kind: .band(from: 10, to: 210, open: 255))
		
		#expect(dimmer.scale(5, by: 0.5) == 5)
		#expect(dimmer.scale(110, by: 0.5) == 60)
		#expect(dimmer.scale(255, by: 0.5) == 110)
		#expect(dimmer.scale(110, by: 1) == 110)
	}
	
	@MainActor @Test func aDimBandCarriesBrightnessBothWays() {
		let shutter = ProfileChannel(offset: 1, role: .shutter, ranges: [
			ChannelRange(from: 0, to: 9, label: "Closed"),
			ChannelRange(from: 10, to: 210, label: "Dimmer", kind: .proportional),
			ChannelRange(from: 211, to: 255, label: "Strobe", kind: .proportional),
		])
		let console = Console()
		let programmer = Programmer(profile: FixtureProfile(id: "t", model: "T", channels: [shutter]), start: DMXAddress(1)!, console: console)
		
		programmer.brightness = 1
		#expect(console.value(at: DMXAddress(1)!) == 210)
		#expect(abs(programmer.brightness - 1) < 0.0001)
		
		programmer.brightness = 0.5
		#expect(console.value(at: DMXAddress(1)!) == 110)
		
		programmer.brightness = 0
		#expect(console.value(at: DMXAddress(1)!) == 0)
		#expect(!programmer.isOn)
	}
	
	@MainActor @Test func sixteenBitChannelsMoveTogether() {
		let profile = FixtureProfile(id: "t", model: "T", channels: [
			ProfileChannel(offset: 1, role: .pan),
			ProfileChannel(offset: 2, role: .pan, isFine: true),
		])
		let console = Console()
		let programmer = Programmer(profile: profile, start: DMXAddress(1)!, console: console)
		
		programmer.setFraction(1, for: .pan)
		#expect(console.value(at: DMXAddress(1)!) == 255)
		#expect(console.value(at: DMXAddress(2)!) == 255)
		
		programmer.setFraction(0.5, for: .pan)
		#expect(abs(programmer.fraction(.pan) - 0.5) < 0.0001)
	}
	
	@MainActor @Test func aSubtractiveHeadTakesColourWithoutTouchingItsDimmer() {
		let profile = FixtureProfile(id: "t", model: "T", channels: [
			ProfileChannel(offset: 1, role: .intensity, defaultValue: 255),
			ProfileChannel(offset: 2, role: .cyan),
			ProfileChannel(offset: 3, role: .magenta),
			ProfileChannel(offset: 4, role: .yellow),
		], mixing: .subtractive)
		let console = Console()
		let programmer = Programmer(profile: profile, start: DMXAddress(1)!, console: console)
		
		programmer.applyDefaults()
		#expect(abs(programmer.brightness - 1) < 0.005)
		
		programmer.apply(LightColor(red: 0, green: 0, blue: 1))
		#expect(console.value(at: DMXAddress(2)!) == 255)
		#expect(console.value(at: DMXAddress(3)!) == 255)
		#expect(console.value(at: DMXAddress(4)!) == 0)
		#expect(abs(programmer.brightness - 1) < 0.005)
	}
	
	@MainActor @Test func patchingWritesTheProfileDefaults() {
		let profile = FixtureProfile(id: "t", model: "T", channels: [
			ProfileChannel(offset: 1, role: .intensity, defaultValue: 255),
			ProfileChannel(offset: 2, role: .pan, defaultValue: 128),
		])
		let console = Console()
		
		Programmer(profile: profile, start: DMXAddress(10)!, console: console).applyDefaults()
		
		#expect(console.value(at: DMXAddress(10)!) == 255)
		#expect(console.value(at: DMXAddress(11)!) == 128)
	}
	
	@MainActor @Test func aSortIndexFollowsTheHighestSoFar() {
		#expect(Console.nextSortIndex([1, 4, 2], sortIndex: \.self) == 5)
		#expect(Console.nextSortIndex([Int](), sortIndex: \.self) == 1)
	}
}
