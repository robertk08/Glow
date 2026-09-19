import Foundation
import SwiftData
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
		let dimmer = Dimmer(address: DMXAddress(1)!, kind: .linear)
		
		#expect(dimmer.scale(200, by: 1) == 200)
		#expect(dimmer.scale(200, by: 0.5) == 100)
		#expect(dimmer.scale(200, by: 0) == 0)
	}
	
	@MainActor @Test func masterScalesInsideADimBandOnly() {
		let dimmer = Dimmer(address: DMXAddress(1)!, kind: .band(from: 10, to: 210, open: 255))
		
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
	
	@Test func aShowPreservesFixtureOrientation() throws {
		let light = ShowFile.Light(identifier: "head", profileID: "moving-head", name: "Head", address: 1, sortIndex: 0, invertsPan: true, invertsTilt: false)
		let file = ShowFile(name: "Show", lights: [light], groups: [], profiles: [], scenes: [])
		let data = try JSONEncoder().encode(file)
		let decoded = try JSONDecoder().decode(ShowFile.self, from: data)
		
		#expect(decoded.lights.first?.invertsPan == true)
		#expect(decoded.lights.first?.invertsTilt == false)
	}
	
	@Test func olderShowsOpenWithoutOrientationFields() throws {
		let data = Data(#"{"name":"Old Show","lights":[{"identifier":"head","profileID":"moving-head","name":"Head","address":1,"sortIndex":0}],"groups":[],"profiles":[],"scenes":[]}"#.utf8)
		let decoded = try JSONDecoder().decode(ShowFile.self, from: data)
		
		#expect(decoded.lights.first?.invertsPan == nil)
		#expect(decoded.lights.first?.invertsTilt == nil)
	}
	
	@MainActor @Test func reorderingKeepsEveryFixture() throws {
		let container = try ModelContainer(for: Fixture.self, FixtureGroup.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
		let fixtures = (0..<3).map { Fixture(profileID: "dimmer", name: "Light \($0)", address: DMXAddress($0 + 1)!, sortIndex: $0) }
		for fixture in fixtures {
			container.mainContext.insert(fixture)
		}
		
		Console().move(IndexSet(integer: 0), to: 3, among: fixtures, sortIndex: \.sortIndex)
		
		#expect(fixtures.map(\.sortIndex) == [2, 0, 1])
		#expect(try container.mainContext.fetchCount(FetchDescriptor<Fixture>()) == 3)
	}
	
	@MainActor @Test func masterAndBlackoutScaleBothDimmerBytes() throws {
		let library = FixtureLibrary()
		let profile = FixtureProfile(id: "test-fine-dimmer", model: "Fine Dimmer", channels: [ProfileChannel(offset: 1, role: .intensity), ProfileChannel(offset: 2, role: .intensity, isFine: true), ProfileChannel(offset: 3, role: .pan)])
		library.setCustom([profile])
		let fixture = Fixture(profileID: profile.id, name: "Dimmer", address: DMXAddress(1)!, sortIndex: 0)
		let console = Console()
		console.applyPatch([fixture], library: library)
		console.set([255, 255, 128], at: DMXAddress(1)!)
		console.master = 0.5
		
		#expect(Array(console.output.prefix(3)) == [128, 0, 128])
		console.blackout = true
		#expect(Array(console.output.prefix(3)) == [0, 0, 128])
		#expect(Array(console.universe.values.prefix(3)) == [255, 255, 128])
	}
	
	@MainActor @Test func bundledFixturesStartOffWithoutASelectedColor() {
		let library = FixtureLibrary()
		#expect(library.bundled.count == 10)
		#expect(Set(library.bundled.map(\.id)).count == library.bundled.count)
		
		for profile in library.bundled {
			let console = Console()
			let programmer = Programmer(profile: profile, start: DMXAddress(1)!, console: console)
			programmer.applyDefaults()
			#expect(programmer.brightness == 0, "\(profile.id) should start off")
			#expect(programmer.selectedPresetID == nil)
			programmer.brightness = 1
			#expect(programmer.brightness > 0.99)
			if profile.mixesColor {
				#expect(programmer.light.red > 0.9 && programmer.light.green > 0.9 && programmer.light.blue > 0.9, "\(profile.id) should open white")
			}
		}
		
		#expect(library.profile("mini-moving-head-14ch")?.invertsTilt == false)
	}
}
