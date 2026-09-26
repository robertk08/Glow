import Foundation
import SwiftData
import Testing

@testable import Glow

@MainActor
private final class Device {
	let console = Console()
	let library = FixtureLibrary()
	let shows = ShowLibrary()
	let opened = Date()
	
	init(host: String) {
		console.endpoint = NodeEndpoint(host: host)
		console.start()
		
		Task { [weak self] in
			while let self {
				self.shows.reach(self.console, library: self.library)
				try? await Task.sleep(for: .milliseconds(20))
			}
		}
	}
	
	var context: ModelContext {
		shows.container.mainContext
	}
	
	var lights: [Fixture] {
		(try? context.fetch(FetchDescriptor<Fixture>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
	}
	
	var scenes: [Look] {
		(try? context.fetch(FetchDescriptor<Look>())) ?? []
	}
	
	func light(_ identifier: String) -> Fixture? {
		lights.first { $0.identifier == identifier }
	}
}

@MainActor
private enum Rig {
	static let host = ProcessInfo.processInfo.environment["GLOW_CONTROLLER"] ?? ""
	static let endpoint = NodeEndpoint(host: host)
	static let first = Device(host: host)
	static let second = Device(host: host)
	static var original = ""
	static var scratch = ""
	
	static var both: [Device] {
		[first, second]
	}
	
	static func stored() async -> ShowContents? {
		await NodeStore().show(scratch, at: endpoint)
	}
}

@MainActor
private func inScratch() throws {
	try #require(!Rig.scratch.isEmpty && Rig.both.allSatisfy { $0.shows.activeID == Rig.scratch }, "the scratch show is not open, so nothing is touched")
}

@MainActor
private func eventually(within seconds: Double = 6, _ condition: () async -> Bool) async -> Double? {
	let start = Date()
	
	while Date().timeIntervalSince(start) < seconds {
		if await condition() { return Date().timeIntervalSince(start) }
		try? await Task.sleep(for: .milliseconds(20))
	}
	
	return nil
}

@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["GLOW_CONTROLLER"] != nil))
struct ControllerTests {
	@Test func bothDevicesOpenTheActiveShow() async throws {
		let took = await eventually(within: 15) { Rig.both.allSatisfy(\.shows.isLoaded) && Rig.first.shows.activeID == Rig.second.shows.activeID }
		
		#expect(took != nil)
		Rig.original = Rig.first.shows.activeID
		print("HARDWARE both devices loaded \(Rig.original) \(String(format: "%.2f", Date().timeIntervalSince(Rig.first.opened)))s after starting")
	}
	
	@Test func aNewShowOpensOnEveryDevice() async throws {
		Rig.first.shows.create(name: "Hardware Test")
		
		let took = await eventually {
			guard let made = Rig.first.shows.shows.first(where: { $0.name.hasPrefix("Hardware Test") }) else { return false }
			Rig.scratch = made.id
			return Rig.both.allSatisfy { $0.shows.activeID == made.id && $0.shows.isLoaded && $0.lights.isEmpty }
		}
		
		#expect(took != nil)
		print("HARDWARE new show open everywhere in \(String(format: "%.2f", took ?? -1))s")
	}
	
	@Test func aLightAddedOnOneDeviceAppearsOnTheOther() async throws {
		try inScratch()
		let light = Fixture(typeID: "stairville-hl-x180-8ch", name: "Probe Wash", address: DMXAddress(10)!, sortIndex: 1)
		Rig.first.context.insert(light)
		try Rig.first.context.save()
		let identifier = light.identifier
		
		let took = await eventually { Rig.second.light(identifier)?.name == "Probe Wash" }
		#expect(took != nil)
		print("HARDWARE light reached the other device in \(String(format: "%.2f", took ?? -1))s")
		
		#expect(await eventually { await Rig.stored()?.lights.contains { $0.identifier == identifier } == true } != nil)
	}
	
	@Test func aRenameAndAMoveReachTheOtherDevice() async throws {
		try inScratch()
		let light = try #require(Rig.first.lights.first)
		light.name = "Renamed Wash"
		light.address = 40
		try Rig.first.context.save()
		let identifier = light.identifier
		
		#expect(await eventually { Rig.second.light(identifier)?.name == "Renamed Wash" && Rig.second.light(identifier)?.address == 40 } != nil)
		#expect(await eventually { await Rig.stored()?.lights.first?.address == 40 } != nil)
	}
	
	@Test func aSceneReachesTheOtherDevice() async throws {
		try inScratch()
		let identifier = try #require(Rig.first.lights.first?.identifier)
		let look = Look(name: "Probe Look", sortIndex: 1, levels: [identifier: Data([255, 0, 128, 7])])
		Rig.first.context.insert(look)
		try Rig.first.context.save()
		let scene = look.identifier
		
		#expect(await eventually { Rig.second.scenes.first { $0.identifier == scene }?.levels[identifier] == Data([255, 0, 128, 7]) } != nil)
		#expect(await eventually { await Rig.stored()?.scenes.count == 1 } != nil)
	}
	
	@Test func anEditedBuiltInFixtureIsKeptAsACopyEverywhere() async throws {
		try inScratch()
		let original = try #require(Rig.first.library.builtIn.first { $0.id == "stairville-bsw350-32ch" })
		var draft = original
		draft.symbol = "lightbulb"
		draft.model = "\(original.model) Custom"
		#expect(!Rig.first.library.isNameTaken(draft))
		Rig.first.library.adopt(draft, replacing: original, among: Rig.first.lights, stored: (try? Rig.first.context.fetch(FetchDescriptor<StoredFixtureType>())) ?? [], context: Rig.first.context)
		try Rig.first.context.save()
		
		#expect(await eventually { Rig.first.library.made.contains { $0.model == draft.model } } != nil)
		let copy = try #require(Rig.first.library.made.first { $0.model == draft.model })
		#expect(copy.id != original.id)
		
		let took = await eventually { Rig.second.library.made.contains { $0.id == copy.id } }
		#expect(took != nil)
		print("HARDWARE edited fixture reached the other device in \(String(format: "%.2f", took ?? -1))s")
		
		#expect(await eventually { await Rig.stored()?.made.contains { $0.id == copy.id } == true } != nil)
	}
	
	@Test func aFixtureMadeFromScratchIsKeptEverywhere() async throws {
		try inScratch()
		var draft = FixtureType.blank
		draft.manufacturer = "Probe"
		draft.model = "Scratch Par"
		Rig.first.library.adopt(draft, replacing: nil, among: Rig.first.lights, stored: (try? Rig.first.context.fetch(FetchDescriptor<StoredFixtureType>())) ?? [], context: Rig.first.context)
		try Rig.first.context.save()
		
		#expect(await eventually { Rig.first.library.made.contains { $0.model == "Scratch Par" } } != nil)
		let made = try #require(Rig.first.library.made.first { $0.model == "Scratch Par" })
		
		#expect(await eventually { Rig.second.library.made.contains { $0.id == made.id } } != nil)
		#expect(await eventually { await Rig.stored()?.made.contains { $0.id == made.id } == true } != nil)
	}
	
	@Test func aFixtureDeletedOnOneDeviceLeavesTheOther() async throws {
		try inScratch()
		let made = try #require(try Rig.first.context.fetch(FetchDescriptor<StoredFixtureType>()).first { $0.definition.model == "Scratch Par" })
		let identifier = made.identifier
		Rig.first.context.delete(made)
		try Rig.first.context.save()
		
		#expect(await eventually { !Rig.second.library.made.contains { $0.id == identifier } } != nil)
		#expect(await eventually { await Rig.stored()?.made.contains { $0.id == identifier } == false } != nil)
	}
	
	@Test func bothDevicesEditingOneLightEndUpAgreeing() async throws {
		try inScratch()
		let identifier = try #require(Rig.first.lights.first?.identifier)
		let mine = try #require(Rig.first.light(identifier))
		let theirs = try #require(Rig.second.light(identifier))
		mine.name = "From First"
		theirs.name = "From Second"
		try Rig.first.context.save()
		try Rig.second.context.save()
		
		let took = await eventually {
			let held = await Rig.stored()?.lights.first { $0.identifier == identifier }?.name
			return held != nil && Rig.first.light(identifier)?.name == held && Rig.second.light(identifier)?.name == held
		}
		
		#expect(took != nil)
		print("HARDWARE both devices agree on \(Rig.first.light(identifier)?.name ?? "nothing")")
	}
	
	@Test func aLightDeletedOnOneDeviceLeavesTheOther() async throws {
		try inScratch()
		let light = try #require(Rig.second.lights.first)
		let identifier = light.identifier
		Rig.second.context.delete(light)
		try Rig.second.context.save()
		
		#expect(await eventually { Rig.first.light(identifier) == nil } != nil)
		#expect(await eventually { await Rig.stored()?.lights.isEmpty == true } != nil)
	}
	
	@Test func anEditMadeWhileTheLinkIsDownNeverReachesTheController() async throws {
		try inScratch()
		let light = Fixture(typeID: "stairville-hl-x180-8ch", name: "Before Drop", address: DMXAddress(100)!, sortIndex: 2)
		Rig.first.context.insert(light)
		try Rig.first.context.save()
		let identifier = light.identifier
		#expect(await eventually { await Rig.stored()?.lights.contains { $0.name == "Before Drop" } == true } != nil)
		
		Rig.first.console.connect()
		#expect(await eventually { !Rig.first.console.link.isConnected } != nil)
		Rig.first.light(identifier)?.name = "During Drop"
		try Rig.first.context.save()
		
		#expect(await eventually { Rig.first.console.link.isConnected && Rig.first.light(identifier)?.name == "Before Drop" } != nil)
		try await Task.sleep(for: .seconds(1))
		#expect(await Rig.stored()?.lights.first { $0.identifier == identifier }?.name == "Before Drop")
	}
	
	@Test func anImportedShowArrivesWholeOnEveryDevice() async throws {
		try inScratch()
		let url = try #require(Bundle.main.url(forResource: "Demo", withExtension: "json"))
		let file = try JSONDecoder.iso.decode(ShowFile.self, from: Data(contentsOf: url))
		#expect(Rig.first.shows.adopt(contentsOf: url))
		
		let took = await eventually(within: 10) {
			Rig.both.allSatisfy { $0.shows.active.name.hasPrefix(file.name) && $0.lights.count == file.show.lights.count && $0.scenes.count == file.show.scenes.count }
		}
		
		#expect(took != nil)
		print("HARDWARE imported show whole on both devices in \(String(format: "%.2f", took ?? -1))s")
		
		let imported = Rig.first.shows.activeID
		let held = await NodeStore().show(imported, at: Rig.endpoint)
		#expect(held?.lights.count == file.show.lights.count)
		#expect(held?.scenes.count == file.show.scenes.count)
		
		Rig.second.shows.delete(Rig.first.shows.active)
		#expect(await eventually { Rig.both.allSatisfy { !$0.shows.shows.contains { $0.id == imported } } } != nil)
	}
	
	@Test func deletingTheOpenShowMovesEveryoneBack() async throws {
		try #require(!Rig.scratch.isEmpty)
		let scratch = try #require(Rig.first.shows.shows.first { $0.id == Rig.scratch })
		Rig.first.shows.activate(scratch)
		#expect(await eventually { Rig.both.allSatisfy { $0.shows.activeID == Rig.scratch && $0.shows.isLoaded } } != nil)
		
		Rig.second.shows.delete(scratch)
		#expect(await eventually { Rig.both.allSatisfy { !$0.shows.shows.contains { $0.id == Rig.scratch } && $0.shows.isLoaded } } != nil)
		
		if let original = Rig.first.shows.shows.first(where: { $0.id == Rig.original }) {
			Rig.first.shows.activate(original)
		}
		
		#expect(await eventually { Rig.both.allSatisfy { $0.shows.activeID == Rig.original && $0.shows.isLoaded } } != nil)
	}
}

private extension JSONDecoder {
	static var iso: JSONDecoder {
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		return decoder
	}
}
