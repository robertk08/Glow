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
	
	@MainActor @Test func aSortIndexFollowsTheHighestSoFar() {
		#expect(Console.nextSortIndex([1, 4, 2], sortIndex: \.self) == 5)
		#expect(Console.nextSortIndex([Int](), sortIndex: \.self) == 1)
	}
	
	@Test func aShowPreservesFixtureOrientation() throws {
		let light = ShowFile.Light(identifier: "head", typeID: "moving-head", name: "Head", address: 1, sortIndex: 0, invertsPan: true, invertsTilt: false)
		let file = ShowFile(name: "Show", lights: [light], groups: [], made: [], scenes: [])
		let data = try JSONEncoder().encode(file)
		let decoded = try JSONDecoder().decode(ShowFile.self, from: data)
		
		#expect(decoded.lights.first?.invertsPan == true)
		#expect(decoded.lights.first?.invertsTilt == false)
	}
	
	@Test func olderShowsOpenWithoutOrientationFields() throws {
		let data = Data(#"{"name":"Old Show","lights":[{"identifier":"head","typeID":"moving-head","name":"Head","address":1,"sortIndex":0}],"groups":[],"made":[],"scenes":[]}"#.utf8)
		let decoded = try JSONDecoder().decode(ShowFile.self, from: data)
		
		#expect(decoded.lights.first?.invertsPan == nil)
		#expect(decoded.lights.first?.invertsTilt == nil)
	}
	
	@Test func aShowWrittenBeforeFixtureTypesStillOpens() throws {
		let data = Data(#"{"name":"Older","lights":[{"identifier":"a","profileID":"mini-moving-head-14ch","name":"Head","address":5,"sortIndex":0}],"groups":[],"profiles":[{"identifier":"x","name":"X","symbol":"star","channels":[]}],"scenes":[]}"#.utf8)
		let decoded = try JSONDecoder().decode(ShowFile.self, from: data)
		
		#expect(decoded.name == "Older")
		#expect(decoded.made.isEmpty)
		#expect(decoded.lights.first?.typeID == "mini-moving-head-14ch")
		#expect(decoded.lights.first?.address == 5)
	}
	
	@MainActor @Test func reorderingKeepsEveryFixture() throws {
		let container = try ModelContainer(for: Fixture.self, FixtureGroup.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
		let fixtures = (0..<3).map { Fixture(typeID: "dimmer", name: "Light \($0)", address: DMXAddress($0 + 1)!, sortIndex: $0) }
		for fixture in fixtures {
			container.mainContext.insert(fixture)
		}
		
		Console().move(IndexSet(integer: 0), to: 3, among: fixtures, sortIndex: \.sortIndex)
		
		#expect(fixtures.map(\.sortIndex) == [2, 0, 1])
		#expect(try container.mainContext.fetchCount(FetchDescriptor<Fixture>()) == 3)
	}
	
	@MainActor @Test func masterAndBlackoutScaleBothDimmerBytes() throws {
		let library = FixtureLibrary()
		let type = FixtureType(id: "test-fine-dimmer", model: "Fine Dimmer", modes: [FixtureType.Mode(id: "fine", name: "3 channel", channels: [FixtureChannel(offset: 1, attribute: .dimmer, fineOffset: 2), FixtureChannel(offset: 3, attribute: .pan)])])
		library.setMade([type])
		let fixture = Fixture(typeID: "fine", name: "Dimmer", address: DMXAddress(1)!, sortIndex: 0)
		let console = Console()
		console.applyPatch([fixture], library: library)
		console.set([255, 255, 128], at: DMXAddress(1)!)
		console.master = 0.5
		
		#expect(Array(console.output.prefix(3)) == [128, 0, 128])
		console.blackout = true
		#expect(Array(console.output.prefix(3)) == [0, 0, 128])
		#expect(Array(console.universe.values.prefix(3)) == [255, 255, 128])
	}
}
