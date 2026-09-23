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
		#expect(Console.nextSortIndex([Double](), sortIndex: \.self) == 1)
	}
	
	@Test func aShowPreservesFixtureOrientation() throws {
		let light = ShowContents.Light(identifier: "head", typeID: "moving-head", name: "Head", address: 1, sortIndex: 0, invertsPan: true, invertsTilt: false)
		let show = ShowContents(lights: [light])
		let decoded = try JSONDecoder().decode(ShowContents.self, from: try JSONEncoder().encode(show))
		
		#expect(decoded.lights.first?.invertsPan == true)
		#expect(decoded.lights.first?.invertsTilt == false)
	}
	
	@Test func aLightCanSitInSeveralGroups() throws {
		let front = ShowContents.Group(identifier: "front", name: "Front", sortIndex: 0)
		let warm = ShowContents.Group(identifier: "warm", name: "Warm", sortIndex: 1)
		let light = ShowContents.Light(identifier: "par", typeID: "par", name: "Par", address: 1, sortIndex: 0, groups: ["front", "warm"])
		let show = ShowContents(lights: [light], groups: [front, warm])
		let decoded = try JSONDecoder().decode(ShowContents.self, from: try JSONEncoder().encode(show))
		
		#expect(decoded.lights.first?.groups == ["front", "warm"])
		#expect(decoded.groups.map(\.identifier) == ["front", "warm"])
	}
	
	@Test func aGroupRenamedKeepsTheIdentifierItsLightsPointAt() throws {
		var group = ShowContents.Group(identifier: "front", name: "Front", sortIndex: 0)
		let light = ShowContents.Light(identifier: "par", typeID: "par", name: "Par", address: 1, sortIndex: 0, groups: ["front"])
		group.name = "Front Truss"
		let show = ShowContents(lights: [light], groups: [group])
		let decoded = try JSONDecoder().decode(ShowContents.self, from: try JSONEncoder().encode(show))
		
		#expect(decoded.groups.first?.name == "Front Truss")
		#expect(decoded.lights.first?.groups == ["front"])
	}
	
	@MainActor @Test func reorderingKeepsEveryFixture() throws {
		let container = try ModelContainer(for: Fixture.self, FixtureGroup.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
		let fixtures = (0..<3).map { Fixture(typeID: "dimmer", name: "Light \($0)", address: DMXAddress($0 + 1)!, sortIndex: Double($0)) }
		for fixture in fixtures {
			container.mainContext.insert(fixture)
		}
		
		Console().move(IndexSet(integer: 0), to: 3, among: fixtures, sortIndex: \.sortIndex)
		
		#expect(fixtures.sorted { $0.sortIndex < $1.sortIndex }.map(\.name) == ["Light 1", "Light 2", "Light 0"])
		#expect(try container.mainContext.fetchCount(FetchDescriptor<Fixture>()) == 3)
	}
	
	@MainActor @Test func aReorderRewritesOnlyTheLightThatMoved() {
		let fixtures = (0..<5).map { Fixture(typeID: "dimmer", name: "Light \($0)", address: DMXAddress($0 + 1)!, sortIndex: Double($0)) }
		let before = fixtures.map(\.sortIndex)
		
		Console().move(IndexSet(integer: 4), to: 0, among: fixtures, sortIndex: \.sortIndex)
		
		#expect(zip(before, fixtures).filter { $0.0 != $0.1.sortIndex }.count == 1)
		#expect(fixtures.sorted { $0.sortIndex < $1.sortIndex }.map(\.name) == ["Light 4", "Light 0", "Light 1", "Light 2", "Light 3"])
	}
	
	@MainActor @Test func droppingBetweenTwoLightsSplitsTheGap() {
		let fixtures = (0..<5).map { Fixture(typeID: "dimmer", name: "Light \($0)", address: DMXAddress($0 + 1)!, sortIndex: Double($0)) }
		let before = fixtures.map(\.sortIndex)
		
		Console().move(IndexSet(integer: 0), to: 3, among: fixtures, sortIndex: \.sortIndex)
		
		#expect(zip(before, fixtures).filter { $0.0 != $0.1.sortIndex }.count == 1)
		#expect(fixtures[0].sortIndex == 2.5)
		#expect(fixtures.sorted { $0.sortIndex < $1.sortIndex }.map(\.name) == ["Light 1", "Light 2", "Light 0", "Light 3", "Light 4"])
	}
	
	@MainActor @Test func masterAndBlackoutScaleBothDimmerBytes() throws {
		let library = FixtureLibrary()
		let type = FixtureType(id: "fine", model: "Fine Dimmer", channels: [FixtureChannel(offset: 1, attribute: .dimmer, fineOffset: 2), FixtureChannel(offset: 3, attribute: .pan)])
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
	
	@MainActor @Test func clashesMatchAPairwiseCheck() {
		let library = FixtureLibrary(builtIn: [])
		let type = FixtureType(id: "four", model: "Four", channels: [FixtureChannel(offset: 1, attribute: .dimmer), FixtureChannel(offset: 4, attribute: .red)])
		library.setMade([type])
		let addresses = [1, 3, 20, 30, 33, 60, 40, 64, 100]
		let fixtures = addresses.enumerated().map { Fixture(typeID: "four", name: "Light \($0.offset)", address: DMXAddress($0.element)!, sortIndex: Double($0.offset)) }
		
		var expected: Set<String> = []
		
		for first in fixtures {
			for second in fixtures where first !== second && first.range(type).overlaps(second.range(type)) {
				expected.insert(first.name)
			}
		}
		
		let found = Fixture.clashing(among: fixtures, library: library)
		
		#expect(Set(fixtures.filter { found.contains($0.persistentModelID) }.map(\.name)) == expected)
	}
	
	@MainActor @Test func aSelectionLetsGoOfLightsThatAreGone() {
		let fixtures = (0..<3).map { Fixture(typeID: "dimmer", name: "Light \($0)", address: DMXAddress($0 + 1)!, sortIndex: Double($0)) }
		let selection = Selection()
		
		for fixture in fixtures {
			selection.toggle(fixture)
		}
		
		selection.keep([fixtures[0].identifier])
		
		#expect(selection.contains(fixtures[0]))
		#expect(!selection.contains(fixtures[1]))
		#expect(selection.identifiers.count == 1)
	}
}

