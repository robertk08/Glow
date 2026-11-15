import Foundation
import Testing

@testable import Glow

struct StageTests {
	@MainActor private static func seeds() throws -> [[UInt8]] {
		let url = try #require(Bundle.main.url(forResource: "Demo", withExtension: "json"))
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		let file = try decoder.decode(ShowFile.self, from: Data(contentsOf: url))
		let library = FixtureLibrary()
		library.setMade(file.show.made)
		var fixtures: [Fixture] = []
		var map = ByteWriter()
		map.byte(Wire.mapOpcode)
		
		for entry in file.show.lights {
			let fixture = Fixture(typeID: entry.typeID, name: entry.name, address: DMXAddress(clamping: entry.address), sortIndex: entry.sortIndex)
			fixture.take(entry, groups: [])
			fixtures.append(fixture)
			library.type(fixture.typeID)?.map(at: fixture.start, into: &map)
		}
		
		var seeds = [[UInt8](map.data)]
		let cues = file.show.cues.map { entry in
			let cue = Cue(lookID: entry.scene, sortIndex: entry.sortIndex, fade: entry.fade, levels: Levels())
			cue.take(entry)
			return cue
		}
		
		for entry in file.show.scenes {
			let look = Look(name: entry.name, sortIndex: entry.sortIndex)
			look.take(entry)
			let list = CueList(look, cues: cues, fixtures: fixtures)
			
			for index in list.cues.indices {
				seeds.append([UInt8](Wire.command(.play, seq: index, scene: look.identifier, body: list.program(from: index))))
				seeds.append([UInt8](Wire.command(.more, seq: index, scene: look.identifier, body: list.program(from: index, snapping: true))))
			}
			
			seeds.append([UInt8](Wire.command(.land, seq: 1, scene: look.identifier, body: list.program(from: 0))))
			seeds.append([UInt8](Wire.command(.stop, seq: 2, scene: look.identifier, body: Data())))
		}
		
		seeds.append([UInt8](Wire.frame([(DMXAddress(1)!, [UInt8](repeating: 200, count: 512))], seq: 1)))
		seeds.append([UInt8](Wire.frame([(DMXAddress(1)!, [1, 2, 3]), (DMXAddress(510)!, [4, 5, 6])], seq: 9)))
		return seeds
	}
	
	@Test(arguments: [UInt64(1), 2, 3, 4])
	func randomMessagesAndClocksNeverCrashThePlaybackEngine(seed: UInt64) async throws {
		let seeds = try await Self.seeds()
		#expect(seeds.count > 20)
		var state = seed &* 0x9E3779B97F4A7C15
		
		func roll(_ count: Int) -> Int {
			state = state &* 6364136223846793005 &+ 1442695040888963407
			return Int((state >> 33) % UInt64(max(count, 1)))
		}
		
		func mutated(_ message: [UInt8]) -> [UInt8] {
			var bytes = message
			
			for _ in 0..<roll(4) {
				switch roll(5) {
				case 0 where !bytes.isEmpty: bytes[roll(bytes.count)] = UInt8(roll(256))
				case 1 where !bytes.isEmpty: bytes.removeSubrange(roll(bytes.count)...)
				case 2: bytes.insert(UInt8(roll(256)), at: roll(bytes.count + 1))
				case 3 where bytes.count > 2: bytes[roll(bytes.count)] = [0, 0x7F, 0x80, 0xFE, 0xFF][roll(5)]
				default: bytes.append(contentsOf: (0..<roll(8)).map { _ in UInt8(roll(256)) })
				}
			}
			
			return bytes
		}
		
		let stage = try #require(stage_new())
		defer { stage_free(stage) }
		var now = UInt32(roll(1000))
		var out = [UInt8](repeating: 0, count: Int(STAGE_FRAME_MAX))
		var values = [UInt8](repeating: 0, count: Int(STAGE_SLOTS) + 1)
		
		for _ in 0..<40000 {
			let message = roll(5) == 0 ? (0..<roll(40)).map { _ in UInt8(roll(256)) } : mutated(seeds[roll(seeds.count)])
			let client = UInt8([0, 1, 7, 8, 0xFF][roll(5)])
			
			switch roll(12) {
			case 0: stage_map(stage, message, message.count)
			case 1: _ = stage_write(stage, message, message.count, client)
			case 2, 3, 4: stage_command(stage, message, message.count, client, now)
			case 5: stage_levels(stage, [0, 0.5, 1, -1, 2, .nan, .infinity][roll(7)], roll(2) == 0)
			case 6: _ = stage_forget(stage, client)
			case 7: stage_clear(stage)
			case 8:
				let room = [0, 1, 3, 7, 100, out.count][roll(6)]
				let count = stage_frame(stage, client, roll(2) == 0, &out, room)
				#expect(count <= room)
			case 9:
				let needed = stage_state(stage, now, nil, 0)
				var held = [UInt8](repeating: 0, count: max(needed, 1))
				let room = [0, 1, 4, needed / 2, needed][roll(5)]
				let count = stage_state(stage, now, &held, min(room, held.count))
				#expect(count <= max(needed, room))
			case 10:
				var from: Int32 = 0
				var to: Int32 = 0
				_ = stage_output(stage, &from, &to)
				stage_scale(stage, &values)
			default: _ = stage_busy(stage)
			}
			
			now &+= UInt32([0, 1, 30, 1000, 70000, UInt32.max / 2][roll(6)])
			_ = stage_tick(stage, now)
		}
	}
}
