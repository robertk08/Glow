import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import Glow

@MainActor
struct CrashTests {
	private struct Dice {
		var state: UInt64
		
		mutating func roll(_ count: Int) -> Int {
			state = state &* 6364136223846793005 &+ 1442695040888963407
			return Int((state >> 33) % UInt64(max(count, 1)))
		}
		
		mutating func byte() -> UInt8 {
			UInt8(roll(256))
		}
		
		mutating func bytes(_ count: Int) -> [UInt8] {
			(0..<count).map { _ in byte() }
		}
		
		mutating func double() -> Double {
			let picks: [Double] = [0, -1, 0.5, 1, 255, 3600, 3601, 1e9, -1e9, 1e300, -1e300, .infinity, -.infinity, .nan, Double(roll(10000)) / 7]
			return picks[roll(picks.count)]
		}
		
		mutating func finite() -> Double {
			let picks: [Double] = [0, -1, 0.5, 1, 255, 256, 65535, 70000, -1e9, Double(roll(70000)) / 7]
			return picks[roll(picks.count)]
		}
		
		mutating func mutated(_ data: Data) -> Data {
			var bytes = [UInt8](data)
			
			for _ in 0...roll(4) {
				switch roll(4) {
				case 0 where !bytes.isEmpty: bytes[roll(bytes.count)] = byte()
				case 1 where !bytes.isEmpty: bytes.removeSubrange(roll(bytes.count)...)
				case 2: bytes.insert(byte(), at: roll(bytes.count + 1))
				default: bytes.append(contentsOf: self.bytes(roll(6)))
				}
			}
			
			return Data(bytes)
		}
	}
	
	nonisolated private static func sampleShow() -> ShowContents {
		var levels = Levels()
		levels.set(200, slot: 1, of: "Abcdefghijk")
		levels.set(7, slot: 40, of: "Abcdefghijk")
		let scene = ShowContents.Scene(identifier: "Scene000001", name: "Scene", sortIndex: 2.5, symbol: "star", tint: "blue", tap: .flash, buttons: SceneAction.allCases, size: .large, loops: true)
		let cue = ShowContents.Cue(identifier: "Cue00000001", scene: scene.identifier, sortIndex: 1, label: "Cue", fade: 1.5, delay: 0.25, follow: 2, levels: levels.data)
		let light = ShowContents.Light(identifier: "Abcdefghijk", typeID: "eight", name: "Light", address: 1, sortIndex: 1, groups: ["Group000001"])
		let group = ShowContents.Group(identifier: "Group000001", name: "Group", sortIndex: 1)
		let type = FixtureType(id: "eight", model: "Eight", channels: [FixtureChannel(offset: 1, attribute: .dimmer), FixtureChannel(offset: 2, attribute: .pan, fineOffset: 3)])
		return ShowContents(lights: [light], groups: [group], made: [type], scenes: [scene], cues: [cue])
	}
	
	@Test nonisolated func randomBytesFromTheControllerNeverCrashAReader() async {
		var dice = Dice(state: 1)
		let show = Self.sampleShow()
		let encoded = ShowLibrary.encoded(show, folders: ShowLibrary.everything)
		var seeds: [Data] = Array(encoded.values)
		seeds.append(Wire.frame([(DMXAddress(1)!, [1, 2, 3]), (DMXAddress(510)!, [4, 5, 6])], seq: 9))
		seeds.append(Wire.document(show: "Show0000001", folder: "scenes", id: "Scene000001", body: show.scenes[0].body))
		seeds.append(Wire.command(.play, seq: 3, scene: "Scene000001", body: Data([1, 2, 3])))
		seeds.append(Data([Wire.commandOpcode, 1, 2, 0, 1, 3, 65, 66, 67, 1, 68, 10, 20, 5, 1, 255]))
		
		for _ in 0..<20000 {
			let data = dice.roll(3) == 0 ? Data(dice.bytes(dice.roll(64))) : dice.mutated(seeds[dice.roll(seeds.count)])
			let bytes = [UInt8](data)
			
			_ = Wire.event(.data(data))
			_ = Wire.runs(in: bytes)
			_ = Wire.objects(in: data)
			_ = Levels(data)
			_ = await MainActor.run { Playback().adopt(bytes, at: .now) }
			
			for folder in NodeStore.Folder.allCases {
				let contents = ShowContents(objects: [(folder.rawValue, "Abcdefghijk", data)])
				_ = ShowLibrary.encoded(contents, folders: ShowLibrary.everything)
				_ = Board(columns: 4, tiles: contents.scenes.map { ($0.identifier, $0.size, Look(name: $0.name, sortIndex: $0.sortIndex).slot) })
			}
			
			if let scene = ShowContents.Scene(identifier: "Scene000001", body: data) {
				#expect(ShowContents.Scene(identifier: "Scene000001", body: scene.body) == scene)
			}
			
			if let cue = ShowContents.Cue(identifier: "Cue00000001", body: data) {
				let again = ShowContents.Cue(identifier: "Cue00000001", body: cue.body)
				#expect(again != nil)
				#expect(again.map { ShowContents.Cue(identifier: "Cue00000001", body: $0.body) == again } == true)
			}
		}
	}
	
	@Test nonisolated func randomTextFromTheControllerNeverCrashesAReader() {
		var dice = Dice(state: 2)
		let kinds = ["status", "locked", "full", "password", "pong", "master", "blackout", "refused", "shows", "wrote", "unwritten", "doc", "x"]
		let values: [String] = ["0", "-1", "1e308", "-1e308", "1.5", "true", "null", "\"\"", "\"a\"", "[]", "{}", "99999999999999999999"]
		let keys = ["level", "on", "show", "folder", "id", "reason", "set", "refused", "wait", "ram", "ramTotal", "store", "storeTotal", "fw", "src", "client", "ip", "own", "wifi", "stored", "master", "blackout", "password", "nonce", "session", "wrong", "active", "shows"]
		
		for _ in 0..<20000 {
			var fields = ["\"t\":\"\(kinds[dice.roll(kinds.count)])\""]
			
			for _ in 0..<dice.roll(16) {
				fields.append("\"\(keys[dice.roll(keys.count)])\":\(values[dice.roll(values.count)])")
			}
			
			_ = Wire.event(.string("{\(fields.joined(separator: ","))}"))
		}
	}
	
	@Test func randomFixtureDefinitionsNeverCrashTheProgrammerOrThePatch() async throws {
		var dice = Dice(state: 3)
		let purposes: [ChannelFunction.Purpose?] = [nil, .dim, .open, .closed, .release]
		let units: [PhysicalUnit?] = [nil, .percent, .degrees, .hertz, .seconds, .kelvin, .rpm]
		let shapes: [GoboShape?] = [nil, .open, .dot, .star]
		
		for round in 0..<800 {
			try await Task.sleep(for: .milliseconds(1))
			var channels: [FixtureChannel] = []
			
			for _ in 0..<(1 + dice.roll(14)) {
				let offset = [1, 2, 3, 4, 8, 16, 0, -1, 600, Int.max, Int.min][dice.roll(11)]
				var channel = FixtureChannel(offset: offset, attribute: Attribute.allCases[dice.roll(Attribute.allCases.count)], fineOffset: dice.roll(4) == 0 ? [offset &+ 1, 513, 0, Int.max][dice.roll(4)] : nil, defaultValue: dice.byte(), fineDefaultValue: dice.byte())
				
				for _ in 0..<dice.roll(5) {
					var function = ChannelFunction(from: dice.byte(), to: dice.byte(), label: "F", kind: dice.roll(2) == 0 ? .setting : .proportional, purpose: purposes[dice.roll(purposes.count)])
					function.unit = units[dice.roll(units.count)]
					function.physicalFrom = dice.roll(3) == 0 ? nil : dice.double()
					function.physicalTo = dice.roll(3) == 0 ? nil : dice.double()
					function.requiresConfirmation = dice.roll(4) == 0
					function.holdSeconds = dice.roll(6) == 0 ? [0.001, 1e300, .infinity, -1][dice.roll(4)] : nil
					function.colors = dice.roll(3) == 0 ? ["ff0000", "zz", "00ff00"] : []
					
					for _ in 0..<dice.roll(4) {
						function.sets.append(ChannelSet(from: dice.byte(), to: dice.byte(), label: "S", colors: [], shape: shapes[dice.roll(shapes.count)]))
					}
					
					channel.functions.append(function)
				}
				
				if dice.roll(4) == 0 {
					channel.enabledBy = FixtureChannel.Dependency(offset: dice.roll(6), from: dice.byte(), to: dice.byte())
				}
				
				channels.append(channel)
			}
			
			let type = FixtureType(id: "fuzz\(round)", model: "Fuzz", mixing: dice.roll(4) == 0 ? .subtractive : .additive, invertsPan: dice.roll(2) == 0, panDegrees: dice.roll(2) == 0 ? dice.double() : nil, tiltDegrees: dice.roll(2) == 0 ? dice.double() : nil, channels: channels)
			let json = try? JSONEncoder().encode(type)
			_ = json.flatMap { try? JSONDecoder().decode(FixtureType.self, from: dice.mutated($0)) }
			guard let used = json.flatMap({ try? JSONDecoder().decode(FixtureType.self, from: $0) }) else { continue }
			
			let library = FixtureLibrary(builtIn: [])
			library.setMade([used])
			let fixtures = [Fixture(typeID: used.id, name: "A", address: DMXAddress(1)!, sortIndex: 0), Fixture(typeID: used.id, name: "B", address: DMXAddress([1, 300, 500, 512][dice.roll(4)])!, sortIndex: 1)]
			let console = Console()
			console.applyPatch(fixtures, library: library)
			_ = Fixture.clashing(among: fixtures, library: library)
			_ = Fixture.firstFreeAddress(width: used.channelCount, among: fixtures, library: library)
			var writer = ByteWriter()
			used.map(at: DMXAddress(500)!, into: &writer)
			
			for programmer in [Programmer(fixtures: fixtures, library: library, console: console), Programmer(type: used, start: DMXAddress(512)!, console: console)] {
				programmer.applyDefaults()
				
				for step in 0..<30 {
					try await Task.sleep(for: .milliseconds(1))
					switch dice.roll(12) {
					case 0: programmer.brightness = dice.double()
					case 1: programmer.setFraction(dice.double(), for: Attribute.allCases[dice.roll(Attribute.allCases.count)])
					case 2: programmer.apply(LightColor(red: dice.finite(), green: dice.finite(), blue: dice.finite()))
					case 3: programmer.apply(kelvin: dice.finite())
					case 4: programmer.toggleOn()
					case 5: programmer.centre()
					case 6: programmer.release(FeatureGroup.allCases[dice.roll(FeatureGroup.allCases.count)])
					case 7: if let preset = programmer.presets.first { programmer.apply(preset) }
					default:
						guard !programmer.channels.isEmpty else { continue }
						let channel = programmer.channels[dice.roll(programmer.channels.count)]
						programmer.set(dice.byte(), of: channel)
						programmer.setRawValue([0, -5, 255, 256, 65535, 70000][dice.roll(6)], of: channel)
						programmer.guardedBinding(channel).wrappedValue = dice.finite()
						programmer.rawBinding(channel).wrappedValue = dice.finite()
						programmer.binding(channel).wrappedValue = dice.finite()
						
						for choice in programmer.modes(of: channel) + programmer.slots(of: channel) + programmer.stops(of: channel) {
							programmer.set(choice.value, of: channel)
							
							Task {
								await programmer.send(choice, of: channel)
							}
						}
						
						_ = (programmer.bandLabel(of: channel), programmer.channelLabel(of: channel), programmer.physical(of: channel), programmer.scale(of: channel), programmer.adjustableBand(of: channel), programmer.blocker(of: channel), programmer.isMarked(channel), programmer.mode(of: channel), programmer.selection(of: channel), programmer.isActive(channel), step)
					}
					
					_ = (programmer.brightness, programmer.light, programmer.kelvin, programmer.selectedPresetID, programmer.strobeHertz, programmer.macroOverridesMix, programmer.degrees(.pan), programmer.degrees(.tilt), programmer.groups, programmer.address, programmer.isOn)
					
					for wheel in programmer.goboWheels {
						_ = (programmer.shape(of: wheel), programmer.standing(of: wheel), programmer.standingAngle(of: programmer.spinner(of: wheel)), programmer.turns(of: programmer.spinner(of: wheel)), programmer.draws(wheel))
					}
				}
			}
		}
	}
	
	@Test func showsWithValuesTheAppNeverWritesStillEncodeArrangeAndPlan() async throws {
		var dice = Dice(state: 4)
		
		for _ in 0..<2000 {
			try await Task.sleep(for: .milliseconds(1))
			var show = Self.sampleShow()
			show.scenes[0].sortIndex = dice.double()
			show.cues[0].sortIndex = dice.double()
			show.cues[0].fade = dice.double()
			show.cues[0].delay = dice.double()
			show.cues[0].follow = dice.roll(2) == 0 ? nil : dice.double()
			show.lights[0].address = [1, 0, -1, 512, 513, Int.max, Int.min][dice.roll(7)]
			show.lights[0].sortIndex = dice.double()
			show.groups[0].sortIndex = dice.double()
			
			let encoded = ShowLibrary.encoded(show, folders: ShowLibrary.everything)
			let back = ShowContents(objects: encoded.map { key, body in
				let parts = key.split(separator: "/", maxSplits: 1)
				return (String(parts[0]), String(parts[1]), body)
			})
			
			for scene in show.scenes + back.scenes {
				let look = Look(name: scene.name, sortIndex: scene.sortIndex)
				let board = Board(columns: 4, tiles: [(look.identifier, scene.size, look.slot)])
				_ = board.rows
			}
			
			let look = Look(name: "Look", sortIndex: 0)
			let cues = (show.cues + back.cues).map { Cue(lookID: look.identifier, sortIndex: $0.sortIndex, fade: $0.fade, levels: Levels($0.levels) ?? Levels()) }
			
			for (cue, entry) in zip(cues, show.cues + back.cues) {
				cue.delay = entry.delay
				cue.follow = entry.follow
				_ = cue.entry.body
			}
			
			let fixture = Fixture(typeID: "eight", name: "Light", address: DMXAddress(1)!, sortIndex: 0)
			let list = CueList(look, cues: cues, fixtures: [fixture])
			
			for index in list.cues.indices {
				_ = list.program(from: index)
				_ = list.program(from: index, snapping: true)
				_ = list.heading(at: index)
				_ = list.tracked(through: index)
			}
		}
	}
}
