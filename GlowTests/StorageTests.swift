import Foundation
import SwiftData
import Testing

@testable import Glow

@MainActor
struct StorageTests {
	private static let filesystem = 0x5F0000
	private static let lights = 50
	private static let channels = 20
	
	private static func record(_ key: String, _ body: Data) -> Int {
		Wire.recordHeader + key.utf8.count - 1 + body.count
	}
	
	private static func rig() -> ShowContents {
		var show = ShowContents()
		show.made = FixtureLibrary().builtIn
		
		for index in 0..<lights {
			show.lights.append(ShowContents.Light(identifier: Identifier.fresh(), typeID: "eight", name: "Light \(index)", address: index * channels + 1, sortIndex: Double(index)))
		}
		
		var whole = Levels()
		var tracked = Levels()
		
		for (index, light) in show.lights.enumerated() {
			let tint: [UInt8] = [[255, 40, 0], [0, 80, 255], [255, 180, 60], [120, 0, 255]][index % 4]
			
			for slot in 1...channels {
				let value: UInt8 = switch slot {
				case 1: 255
				case 2...4: tint[slot - 2]
				case 12: 128
				default: 0
				}
				whole.set(value, slot: slot, of: light.identifier)
			}
			
			if index < 12 {
				tracked.set(200, slot: 1, of: light.identifier)
				
				for slot in 2...4 {
					tracked.set(tint[slot - 2] / 2, slot: slot, of: light.identifier)
				}
			}
		}
		
		show.scenes = [ShowContents.Scene(identifier: Identifier.fresh(), name: "Look", sortIndex: 0)]
		show.cues = [
			ShowContents.Cue(identifier: Identifier.fresh(), scene: show.scenes[0].identifier, sortIndex: 1, label: "Whole", fade: 3, levels: whole.data),
			ShowContents.Cue(identifier: Identifier.fresh(), scene: show.scenes[0].identifier, sortIndex: 2, label: "Tracked", fade: 3, levels: tracked.data),
		]
		return show
	}
	
	private static func cue(named name: String, in files: [String: Data], of show: ShowContents) throws -> (key: String, body: Data) {
		let identifier = try #require(show.cues.first { $0.label == name }?.identifier)
		let key = "cues/\(identifier)"
		return (key, try #require(files[key]))
	}
	
	@Test func everyFixtureDefinitionComesBackFromStorage() throws {
		var blank = FixtureType.blank
		blank.id = "scratch-made"
		blank.model = "Scratch"
		
		for definition in FixtureLibrary().builtIn + [blank] {
			let container = try ModelContainer(for: StoredFixtureType.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
			container.mainContext.insert(StoredFixtureType(definition))
			try container.mainContext.save()
			
			let stored = try ModelContext(container).fetch(FetchDescriptor<StoredFixtureType>())
			#expect(stored.map(\.definition) == [definition])
		}
	}
	
	@Test func aWholeLookCostsLessThanFifteenBytesPerLight() async throws {
		let show = Self.rig()
		let files = await ShowLibrary.snapshot(of: show, folders: [.cues])
		let whole = try Self.cue(named: "Whole", in: files, of: show)
		
		#expect(whole.body.count / Self.lights < 15)
	}
	
	@Test func aTrackedCueCostsLessThanTwentyBytesPerLightItChanges() async throws {
		let show = Self.rig()
		let files = await ShowLibrary.snapshot(of: show, folders: [.cues])
		let tracked = try Self.cue(named: "Tracked", in: files, of: show)
		
		#expect(tracked.body.count / 12 < 20)
	}
	
	@Test func aLightCostsLessThanOneHundredTwentyBytes() async throws {
		let show = Self.rig()
		let files = await ShowLibrary.snapshot(of: show, folders: [.lights])
		let light = try #require(files.values.max(by: { $0.count < $1.count }))
		
		#expect(light.count < 120)
	}
	
	@Test func theBundledDefinitionsFitInSixtyKilobytes() async {
		let show = Self.rig()
		let files = await ShowLibrary.snapshot(of: show, folders: [.made])
		let total = files.values.reduce(0) { $0 + $1.count }
		
		#expect(files.count == 4)
		#expect(total < 60_000)
	}
	
	@Test func oneFiftyLightShowHoldsTenThousandCuesOrFourThousandWholeLooks() async throws {
		let show = Self.rig()
		let files = await ShowLibrary.snapshot(of: show)
		let whole = try Self.cue(named: "Whole", in: files, of: show)
		let tracked = try Self.cue(named: "Tracked", in: files, of: show)
		let scene = try #require(files.first { $0.key.hasPrefix("scenes/") })
		
		var fixed = 0
		
		for (key, data) in files where !key.hasPrefix("cues/") && !key.hasPrefix("scenes/") {
			fixed += Self.record(key, data)
		}
		
		let room = Self.filesystem / 2 - fixed
		
		#expect(room / Self.record(tracked.key, tracked.body) >= 10_000)
		#expect(room / (Self.record(whole.key, whole.body) + Self.record(scene.key, scene.value)) >= 4_000)
	}
	
	@Test func theWholeShowIsATinyShareOfTheFilesystem() async {
		let files = await ShowLibrary.snapshot(of: Self.rig())
		let total = files.reduce(0) { $0 + Self.record($1.key, $1.value) }
		
		#expect(total < Self.filesystem / 8)
	}
}
