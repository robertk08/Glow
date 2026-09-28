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
		if let key = Rig.key {
			Passkey.store(key, id: Rig.id)
		}
		
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
	
	var looks: [Look] {
		(try? context.fetch(FetchDescriptor<Look>())) ?? []
	}
	
	var cues: [Cue] {
		(try? context.fetch(FetchDescriptor<Cue>())) ?? []
	}
	
	func light(_ identifier: String) -> Fixture? {
		lights.first { $0.identifier == identifier }
	}
}

@MainActor
private enum Rig {
	static let host = ProcessInfo.processInfo.environment["GLOW_CONTROLLER"] ?? ""
	static let endpoint = NodeEndpoint(host: host)
	static let key = hex(ProcessInfo.processInfo.environment["GLOW_KEY"] ?? "")
	static let id = ((try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(string: "http://\(host)/api/info")!))) as? [String: Any])?["id"] as? String ?? ""
	static let first = Device(host: host)
	static let second = Device(host: host)
	static var original = ""
	static var scratch = ""
	
	static var both: [Device] {
		[first, second]
	}
	
	static func stored() async -> ShowContents? {
		await NodeStore().show(scratch, at: first.console.reachable)
	}
	
	static func hex(_ text: String) -> Data? {
		let digits = Array(text.utf8)
		guard digits.count == 64 else { return nil }
		return Data(stride(from: 0, to: digits.count, by: 2).compactMap { UInt8(String(decoding: digits[$0..<$0 + 2], as: UTF8.self), radix: 16) })
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
private func stall() async throws -> URLSessionStreamTask {
	let stream = URLSession.shared.streamTask(withHostName: Rig.host, port: 80)
	stream.resume()
	try await stream.write(Data("GET /ws HTTP/1.1\r\nHost: \(Rig.host)\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n".utf8), timeout: 2)
	let (answer, _) = try await stream.readData(ofMinLength: 12, maxLength: 512, timeout: 2)
	try #require(String(decoding: answer ?? Data(), as: UTF8.self).contains(" 101 "))
	try await stream.write(Data([0x82, 0xFE, 0x03, 0xE8, 1, 2, 3, 4] + [UInt8](repeating: 0, count: 10)), timeout: 2)
	return stream
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
	
	@Test func aSceneAndItsCuesReachTheOtherDevice() async throws {
		try inScratch()
		let identifier = try #require(Rig.first.lights.first?.identifier)
		let look = Look(name: "Probe Scene", sortIndex: 1)
		var opening = Levels()
		opening.set(255, slot: 8, of: identifier)
		opening.set(128, slot: 1, of: identifier)
		var closing = Levels()
		closing.set(40, slot: 8, of: identifier)
		let second = Cue(lookID: look.identifier, sortIndex: 2, fade: 0.3, levels: closing)
		Rig.first.context.insert(look)
		Rig.first.context.insert(Cue(lookID: look.identifier, sortIndex: 1, fade: 0, levels: opening))
		Rig.first.context.insert(second)
		try Rig.first.context.save()
		let scene = look.identifier
		let cue = second.identifier
		
		let took = await eventually { Rig.second.looks.contains { $0.identifier == scene } && Rig.second.cues.first { $0.identifier == cue }?.levels == closing }
		#expect(took != nil)
		print("HARDWARE scene and cues reached the other device in \(String(format: "%.2f", took ?? -1))s")
		
		#expect(await eventually {
			let held = await Rig.stored()
			return held?.scenes.count == 1 && held?.cues.count == 2 && held?.unreadable.isEmpty == true
		} != nil)
	}
	
	@Test func goAndOffOnOneDeviceReachTheOther() async throws {
		try inScratch()
		let look = try #require(Rig.first.looks.first { $0.name == "Probe Scene" })
		let light = try #require(Rig.first.lights.first)
		let dimmer = try #require(DMXAddress(light.address + 7))
		let list = CueList(look, cues: Rig.first.cues, fixtures: Rig.first.lights)
		try #require(list.cues.count == 2)
		
		let before = Rig.first.console.value(at: dimmer)
		
		Rig.first.console.go(list)
		#expect(await eventually { Rig.second.console.playback.cue(of: look.identifier) == list.cues[0].identifier && Rig.second.console.value(at: dimmer) == 255 } != nil)
		
		Rig.first.console.go(list)
		let took = await eventually { Rig.second.console.playback.cue(of: look.identifier) == list.cues[1].identifier && Rig.second.console.value(at: dimmer) == 40 }
		#expect(took != nil)
		print("HARDWARE a 0.3 s fade on one device finished on the other in \(String(format: "%.2f", took ?? -1))s")
		
		let theirs = CueList(look, cues: Rig.second.cues, fixtures: Rig.second.lights)
		Rig.second.console.toggle(theirs)
		let back = await eventually { Rig.first.console.playback.cue(of: look.identifier) == nil && Rig.first.console.value(at: dimmer) == before }
		#expect(back != nil)
		print("HARDWARE turning it off on the other device put the light back in \(String(format: "%.2f", back ?? -1))s")
	}
	
	@Test func aCueReachesTheOtherDeviceQuickly() async throws {
		try inScratch()
		let light = try #require(Rig.first.lights.first)
		let dimmer = try #require(DMXAddress(light.address + 7))
		let look = Look(name: "Probe Steps", sortIndex: 2)
		var high = Levels()
		high.set(200, slot: 8, of: light.identifier)
		var low = Levels()
		low.set(100, slot: 8, of: light.identifier)
		Rig.first.context.insert(look)
		Rig.first.context.insert(Cue(lookID: look.identifier, sortIndex: 1, fade: 0, levels: high))
		Rig.first.context.insert(Cue(lookID: look.identifier, sortIndex: 2, fade: 0, levels: low))
		try Rig.first.context.save()
		#expect(await eventually { Rig.second.cues.count { $0.lookID == look.identifier } == 2 } != nil)
		let list = CueList(look, cues: Rig.first.cues, fixtures: Rig.first.lights)
		var took: [Double] = []
		
		for step in 0..<40 {
			Rig.first.console.go(list)
			let wanted: UInt8 = step % 2 == 0 ? 200 : 100
			let start = Date()
			
			while Rig.second.console.value(at: dimmer) != wanted, Date().timeIntervalSince(start) < 2 {
				try await Task.sleep(for: .milliseconds(1))
			}
			
			took.append(Date().timeIntervalSince(start) * 1000)
			try await Task.sleep(for: .milliseconds(30))
		}
		
		let sorted = took.sorted()
		#expect(sorted[35] < 150)
		print("HARDWARE a cue reached the other device in p50 \(Int(sorted[20])) ms, p90 \(Int(sorted[36])) ms, worst \(Int(sorted[39])) ms, controller RAM \(Rig.first.console.usage.map { "\($0.memory / 1024) KB of \($0.memoryTotal / 1024) KB" } ?? "unknown")")
		
		Rig.first.console.stop(list, snapping: true)
		#expect(await eventually { Rig.second.console.playback.cue(of: look.identifier) == nil } != nil)
	}
	
	@Test func aFadeGlidesSmoothlyOnTheOtherDevice() async throws {
		try inScratch()
		let light = try #require(Rig.first.lights.first)
		let dimmer = try #require(DMXAddress(light.address + 7))
		let look = Look(name: "Probe Fade", sortIndex: 3)
		var up = Levels()
		up.set(255, slot: 8, of: light.identifier)
		Rig.first.context.insert(look)
		Rig.first.context.insert(Cue(lookID: look.identifier, sortIndex: 1, fade: 1, levels: up))
		try Rig.first.context.save()
		#expect(await eventually { Rig.second.cues.contains { $0.lookID == look.identifier } } != nil)
		let list = CueList(look, cues: Rig.first.cues, fixtures: Rig.first.lights)
		let before = Rig.second.console.value(at: dimmer)
		
		Rig.first.console.go(list)
		let start = Date()
		var changes: [Double] = []
		var last = before
		
		while Date().timeIntervalSince(start) < 2.5 {
			let now = Rig.second.console.value(at: dimmer)
			if now != last { changes.append(Date().timeIntervalSince(start) * 1000) }
			last = now
			try await Task.sleep(for: .milliseconds(1))
		}
		
		let gaps = zip(changes.dropFirst(), changes).map { $0 - $1 }.sorted()
		#expect(last == 255)
		#expect(changes.count > 15)
		print("HARDWARE a 1 s fade showed \(changes.count) steps on the other device, gap p90 \(gaps.isEmpty ? -1 : Int(gaps[gaps.count * 9 / 10])) ms, worst \(Int(gaps.last ?? -1)) ms, done after \(Int(changes.last ?? -1)) ms")
		
		Rig.first.console.stop(list, snapping: true)
		#expect(await eventually { Rig.second.console.value(at: dimmer) == before } != nil)
	}
	
	@Test func aFadeCarriesOnWhenTheDeviceThatStartedItDrops() async throws {
		try inScratch()
		let light = try #require(Rig.first.lights.first)
		let dimmer = try #require(DMXAddress(light.address + 7))
		let look = try #require(Rig.first.looks.first { $0.name == "Probe Fade" })
		let list = CueList(look, cues: Rig.first.cues, fixtures: Rig.first.lights)
		let before = Rig.second.console.value(at: dimmer)
		
		Rig.first.console.go(list)
		try await Task.sleep(for: .milliseconds(100))
		Rig.first.console.connect()
		#expect(await eventually { !Rig.first.console.link.isConnected } != nil)
		var seen: Set<UInt8> = []
		
		let took = await eventually(within: 3) {
			seen.insert(Rig.second.console.value(at: dimmer))
			return Rig.second.console.value(at: dimmer) == 255
		}
		
		#expect(took != nil)
		#expect(seen.count > 5)
		print("HARDWARE a fade went on to the end on the other device \(String(format: "%.2f", took ?? -1))s after the device that started it dropped, through \(seen.count) steps")
		
		#expect(await eventually { Rig.first.console.link.isConnected && Rig.first.shows.isLoaded } != nil)
		Rig.first.console.stop(CueList(look, cues: Rig.first.cues, fixtures: Rig.first.lights), snapping: true)
		#expect(await eventually { Rig.second.console.value(at: dimmer) == before } != nil)
	}
	
	@Test func aValueSetMidFadeHoldsOnEveryDeviceAndStaysWhenTheSceneGoesOff() async throws {
		try inScratch()
		let light = try #require(Rig.first.lights.first)
		let dimmer = try #require(DMXAddress(light.address + 7))
		let look = Look(name: "Probe Takeover", sortIndex: 5)
		var up = Levels()
		up.set(255, slot: 8, of: light.identifier)
		Rig.first.context.insert(look)
		Rig.first.context.insert(Cue(lookID: look.identifier, sortIndex: 1, fade: 2, levels: up))
		try Rig.first.context.save()
		#expect(await eventually { Rig.second.cues.contains { $0.lookID == look.identifier } } != nil)
		let list = CueList(look, cues: Rig.first.cues, fixtures: Rig.first.lights)
		Rig.first.console.set(0, at: dimmer)
		#expect(await eventually { Rig.second.console.value(at: dimmer) == 0 } != nil)
		
		Rig.first.console.go(list)
		#expect(await eventually { (30...220).contains(Rig.second.console.value(at: dimmer)) } != nil)
		Rig.first.console.set(77, at: dimmer)
		let took = await eventually { Rig.both.allSatisfy { $0.console.value(at: dimmer) == 77 } }
		
		#expect(took != nil)
		try await Task.sleep(for: .milliseconds(2200))
		#expect(Rig.both.allSatisfy { $0.console.value(at: dimmer) == 77 })
		print("HARDWARE a value set mid fade held on both devices after \(String(format: "%.2f", took ?? -1))s and the fade never took it back")
		
		Rig.second.console.toggle(CueList(look, cues: Rig.second.cues, fixtures: Rig.second.lights))
		#expect(await eventually { Rig.first.console.playback.cue(of: look.identifier) == nil } != nil)
		try await Task.sleep(for: .milliseconds(200))
		#expect(Rig.both.allSatisfy { $0.console.value(at: dimmer) == 77 })
	}
	
	@Test func aChaseTooLongToSendAtOnceRunsThroughEveryCue() async throws {
		try inScratch()
		var lights: [Fixture] = []
		
		for index in 0..<10 {
			let light = Fixture(typeID: "stairville-bsw350-32ch", name: "Chase \(index + 1)", address: DMXAddress(100 + index * 32)!, sortIndex: Double(10 + index))
			Rig.first.context.insert(light)
			lights.append(light)
		}
		
		let look = Look(name: "Probe Chase", sortIndex: 6)
		Rig.first.context.insert(look)
		
		for step in 0..<40 {
			var levels = Levels()
			
			for light in lights {
				for slot in 1...32 {
					levels.set(UInt8(step + 1), slot: slot, of: light.identifier)
				}
			}
			
			let cue = Cue(lookID: look.identifier, sortIndex: Double(step), fade: 0, levels: levels)
			cue.follow = 0.05
			Rig.first.context.insert(cue)
		}
		
		try Rig.first.context.save()
		#expect(await eventually(within: 20) { Rig.second.cues.count { $0.lookID == look.identifier } == 40 && Rig.second.lights.count == Rig.first.lights.count } != nil)
		let list = CueList(look, cues: Rig.first.cues, fixtures: Rig.first.lights)
		let first = try #require(DMXAddress(100))
		var seen: Set<UInt8> = []
		
		Rig.first.console.go(list)
		let took = await eventually(within: 10) {
			seen.insert(Rig.second.console.value(at: first))
			return seen.isSuperset(of: Set(1...40))
		}
		
		#expect(took != nil)
		print("HARDWARE a 40 cue chase too long for one command showed every cue on the other device within \(String(format: "%.2f", took ?? -1))s")
		
		Rig.first.console.stop(list, snapping: true)
		#expect(await eventually { Rig.second.console.playback.cue(of: look.identifier) == nil } != nil)
		Rig.first.console.remove(look, with: Rig.first.cues, context: Rig.first.context)
		
		for light in lights {
			Rig.first.context.delete(light)
		}
		
		try Rig.first.context.save()
		#expect(await eventually(within: 20) { Rig.second.lights.count == Rig.first.lights.count && !Rig.second.looks.contains { $0.identifier == look.identifier } } != nil)
	}
	
	@Test func aChaseKeepsItsTimeWhileAPhoneHoldsTheControllerMidMessage() async throws {
		try inScratch()
		let light = try #require(Rig.first.lights.first)
		let dimmer = try #require(DMXAddress(light.address + 7))
		let look = Look(name: "Probe Stall", sortIndex: 7)
		Rig.first.context.insert(look)
		
		for step in 0..<10 {
			var levels = Levels()
			levels.set(UInt8(step * 20 + 10), slot: 8, of: light.identifier)
			let cue = Cue(lookID: look.identifier, sortIndex: Double(step), fade: 0, levels: levels)
			cue.follow = 0.2
			Rig.first.context.insert(cue)
		}
		
		try Rig.first.context.save()
		#expect(await eventually { Rig.second.cues.count { $0.lookID == look.identifier } == 10 } != nil)
		let list = CueList(look, cues: Rig.first.cues, fixtures: Rig.first.lights)
		
		Rig.first.console.go(list)
		let started = Date()
		try await Task.sleep(for: .milliseconds(300))
		let stalled = try await stall()
		try await Task.sleep(for: .milliseconds(200))
		let frozen = Rig.second.console.value(at: dimmer)
		var moved = false
		
		for _ in 0..<250 {
			moved = moved || Rig.second.console.value(at: dimmer) != frozen
			try await Task.sleep(for: .milliseconds(10))
		}
		
		stalled.cancel()
		try await Task.sleep(for: .milliseconds(150))
		let expected = Int(Date().timeIntervalSince(started) / 0.2) % 10
		let reached = try #require(list.index(of: Rig.second.console.playback.cue(of: look.identifier)))
		
		#expect(!moved, "the controller never stalled, so this proves nothing")
		#expect([9, 0, 1].contains((reached - expected + 10) % 10))
		print("HARDWARE after a phone held the controller mid message for 2.5 s the chase was on cue \(reached + 1) of 10, its clock said \(expected + 1)")
		
		Rig.first.console.stop(list, snapping: true)
		#expect(await eventually { Rig.second.console.playback.cue(of: look.identifier) == nil } != nil)
	}
	
	@Test func twoDevicesStartingCuesTogetherEndOnTheLastOne() async throws {
		try inScratch()
		let light = try #require(Rig.first.lights.first)
		let dimmer = try #require(DMXAddress(light.address + 7))
		let look = Look(name: "Probe Race", sortIndex: 4)
		var bright = Levels()
		bright.set(250, slot: 8, of: light.identifier)
		var dim = Levels()
		dim.set(60, slot: 8, of: light.identifier)
		Rig.first.context.insert(look)
		Rig.first.context.insert(Cue(lookID: look.identifier, sortIndex: 1, fade: 1.5, levels: bright))
		Rig.first.context.insert(Cue(lookID: look.identifier, sortIndex: 2, fade: 1, levels: dim))
		try Rig.first.context.save()
		#expect(await eventually { Rig.second.cues.count { $0.lookID == look.identifier } == 2 } != nil)
		let mine = CueList(look, cues: Rig.first.cues, fixtures: Rig.first.lights)
		let theirs = CueList(look, cues: Rig.second.cues, fixtures: Rig.second.lights)
		
		Rig.first.console.go(mine)
		try await Task.sleep(for: .milliseconds(500))
		Rig.second.console.go(theirs)
		try await Task.sleep(for: .milliseconds(2500))
		
		print("HARDWARE two devices stepping one scene ended on \(Rig.first.console.value(at: dimmer)) and \(Rig.second.console.value(at: dimmer)), wanted 60")
		#expect(Rig.both.allSatisfy { $0.console.value(at: dimmer) == 60 })
		#expect(Rig.both.allSatisfy { $0.console.playback.cue(of: look.identifier) == mine.cues[1].identifier })
		
		Rig.first.console.stop(mine, snapping: true)
		#expect(await eventually { Rig.second.console.playback.cue(of: look.identifier) == nil } != nil)
	}
	
	@Test func twoDevicesHammeringOneSceneStillAgree() async throws {
		try inScratch()
		let light = try #require(Rig.first.lights.first)
		let dimmer = try #require(DMXAddress(light.address + 7))
		let look = try #require(Rig.first.looks.first { $0.name == "Probe Steps" })
		let mine = CueList(look, cues: Rig.first.cues, fixtures: Rig.first.lights)
		let theirs = CueList(look, cues: Rig.second.cues, fixtures: Rig.second.lights)
		
		for step in 0..<60 {
			if step % 2 == 0 {
				Rig.first.console.go(mine)
			} else {
				Rig.second.console.go(theirs)
			}
			
			try await Task.sleep(for: .milliseconds(step % 3 == 0 ? 1 : 12))
		}
		
		try await Task.sleep(for: .milliseconds(400))
		let took = await eventually {
			let cue = Rig.first.console.playback.cue(of: look.identifier)
			return cue != nil && cue == Rig.second.console.playback.cue(of: look.identifier) && Rig.first.console.value(at: dimmer) == Rig.second.console.value(at: dimmer) && [100, 200].contains(Rig.first.console.value(at: dimmer))
		}
		
		#expect(took != nil)
		let cue = Rig.first.console.playback.cue(of: look.identifier)
		#expect(Rig.first.console.value(at: dimmer) == (cue == mine.cues[0].identifier ? 200 : 100))
		print("HARDWARE 60 steps from two devices settled on one cue everywhere, controller RAM \(Rig.first.console.usage.map { "\($0.memory / 1024) KB" } ?? "unknown")")
		
		Rig.first.console.stop(mine, snapping: true)
		#expect(await eventually { Rig.second.console.playback.cue(of: look.identifier) == nil } != nil)
	}
	
	@Test func aCueStoredOnOneDeviceIsOnStageOnTheOther() async throws {
		try inScratch()
		let look = try #require(Rig.first.looks.first { $0.name == "Probe Scene" })
		let light = try #require(Rig.first.lights.first)
		let dimmer = try #require(DMXAddress(light.address + 7))
		let list = CueList(look, cues: Rig.first.cues, fixtures: Rig.first.lights)
		let first = try #require(Rig.first.cues.first { $0.identifier == list.cues[0].identifier })
		
		Rig.first.console.play(list, at: 0, snapping: true)
		Rig.first.console.set(99, at: dimmer)
		Recording(.cue(look, after: first), console: Rig.first.console, fixtures: Rig.first.lights, library: Rig.first.library, looks: Rig.first.looks, cues: Rig.first.cues).store(context: Rig.first.context)
		let stored = try #require(Rig.first.console.playback.cue(of: look.identifier))
		
		let took = await eventually { Rig.second.cues.contains { $0.identifier == stored } && Rig.second.console.playback.cue(of: look.identifier) == stored && Rig.second.console.value(at: dimmer) == 99 }
		#expect(took != nil)
		#expect(look.cues(among: Rig.first.cues).map(\.identifier) == [list.cues[0].identifier, stored, list.cues[1].identifier])
		print("HARDWARE a cue stored between two others was on stage on the other device in \(String(format: "%.2f", took ?? -1))s")
		
		Rig.first.console.stop(CueList(look, cues: Rig.first.cues, fixtures: Rig.first.lights), snapping: true)
		#expect(await eventually { Rig.second.console.playback.cue(of: look.identifier) == nil } != nil)
	}
	
	@Test func aSceneInTheOldFormatIsErasedWhenItsShowOpens() async throws {
		try inScratch()
		let old = Data(#"{"identifier":"0908ef53afc76309","levels":{},"name":"Open White","sortIndex":0}"#.utf8)
		#expect(await NodeStore().put(old, folder: .scenes, id: "0908ef53afc76309", in: Rig.scratch, at: Rig.first.console.reachable, client: nil))
		#expect(await eventually { await Rig.stored()?.unreadable == ["scenes/0908ef53afc76309"] } != nil)
		
		Rig.first.console.connect()
		let took = await eventually(within: 10) { await Rig.stored()?.unreadable.isEmpty == true }
		#expect(took != nil)
		#expect(Rig.both.allSatisfy { device in !device.looks.contains { $0.identifier == "0908ef53afc76309" } })
		print("HARDWARE an old scene was erased \(String(format: "%.2f", took ?? -1))s after its show reopened")
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
		try await Task.sleep(for: .milliseconds(500))
		#expect(await Rig.stored()?.lights.first { $0.identifier == identifier }?.name == "Before Drop")
	}
	
	@Test func anImportedShowArrivesWholeOnEveryDevice() async throws {
		try inScratch()
		let url = try #require(Bundle.main.url(forResource: "Demo", withExtension: "json"))
		var file = try JSONDecoder.iso.decode(ShowFile.self, from: Data(contentsOf: url))
		file.show.lights = Array(file.show.lights.prefix(3))
		file.show.scenes = Array(file.show.scenes.prefix(4))
		file.show.cues = file.show.cues.filter { cue in file.show.scenes.contains { $0.identifier == cue.scene } }
		file.show.groups = []
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		let trimmed = FileManager.default.temporaryDirectory.appending(path: "Trimmed.json")
		try encoder.encode(file).write(to: trimmed)
		#expect(Rig.first.shows.adopt(contentsOf: trimmed))
		
		let took = await eventually(within: 10) {
			Rig.both.allSatisfy { $0.shows.active.name.hasPrefix(file.name) && $0.lights.count == file.show.lights.count && $0.looks.count == file.show.scenes.count && $0.cues.count == file.show.cues.count }
		}
		
		#expect(took != nil)
		print("HARDWARE imported show whole on both devices in \(String(format: "%.2f", took ?? -1))s")
		
		let imported = Rig.first.shows.activeID
		let held = await NodeStore().show(imported, at: Rig.first.console.reachable)
		#expect(held?.lights.count == file.show.lights.count)
		#expect(held?.scenes.count == file.show.scenes.count)
		#expect(held?.cues.count == file.show.cues.count)
		
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
	
	@Test func aPasswordLocksOutEveryOtherDevice() async throws {
		let node = try #require(Rig.first.console.node)
		let id = node.id
		
		if node.hasPassword {
			Rig.first.console.send(.password(old: Rig.key, new: nil, nonce: node.nonce))
			try #require(await eventually { Rig.first.console.node?.hasPassword == false } != nil, "the key read from the controller did not remove its password")
		}
		
		Rig.first.console.protect(current: "", new: "probe-pass")
		
		#expect(await eventually { Rig.first.console.passwordOutcome == .saved } != nil)
		Passkey.forget(id: id)
		#expect(Rig.first.console.node?.hasPassword == true)
		
		let took = await eventually { Rig.second.console.link == .locked && Rig.second.console.lock != nil }
		#expect(took != nil)
		print("HARDWARE the other device was locked out in \(String(format: "%.2f", took ?? -1))s")
		
		#expect(Rig.first.console.link.isConnected)
		#expect(Rig.second.console.link == .locked)
		#expect(await NodeStore().show(Rig.original, at: Rig.endpoint) == nil)
		#expect(await NodeStore().show(Rig.original, at: Rig.first.console.reachable) != nil)
	}
	
	@Test func aWrongPasswordIsTurnedDown() async throws {
		try #require(Rig.second.console.link == .locked)
		Rig.second.console.unlock(password: "not it")
		
		#expect(await eventually { Rig.second.console.lock?.isWrong == true && !Rig.second.console.isUnlocking } != nil)
		#expect(Rig.second.console.link == .locked)
	}
	
	@Test func theRightPasswordIsAskedForOncePerDevice() async throws {
		let id = try #require(Rig.first.console.node?.id)
		Rig.second.console.unlock(password: "probe-pass")
		
		let took = await eventually(within: 10) { Rig.second.console.link.isConnected && Rig.second.console.lock == nil && Rig.second.shows.isLoaded }
		#expect(took != nil)
		#expect(Passkey.stored(id: id) != nil)
		print("HARDWARE unlocked and loaded in \(String(format: "%.2f", took ?? -1))s")
		
		Rig.second.console.connect()
		#expect(await eventually { !Rig.second.console.link.isConnected } != nil)
		let again = await eventually(within: 10) { Rig.second.console.link.isConnected && Rig.second.shows.isLoaded }
		#expect(again != nil)
		print("HARDWARE reconnected without asking in \(String(format: "%.2f", again ?? -1))s")
	}
	
	@Test func changingThePasswordNeedsTheCurrentOne() async throws {
		Rig.first.console.protect(current: "not it", new: "probe-pass-2")
		
		#expect(await eventually { Rig.first.console.passwordOutcome == .wrong(wait: 0) } != nil)
		#expect(Rig.second.console.link.isConnected)
	}
	
	@Test func aChangedPasswordLocksTheOthersOutAgain() async throws {
		let id = try #require(Rig.first.console.node?.id)
		Rig.first.console.protect(current: "probe-pass", new: "probe-pass-2")
		
		#expect(await eventually { Rig.first.console.passwordOutcome == .saved } != nil)
		Passkey.forget(id: id)
		#expect(await eventually { Rig.second.console.link == .locked && Rig.second.console.lock != nil } != nil)
		
		Rig.second.console.unlock(password: "probe-pass")
		#expect(await eventually { Rig.second.console.lock?.isWrong == true && !Rig.second.console.isUnlocking } != nil)
	}
	
	@Test func removingThePasswordOpensTheControllerAgain() async throws {
		let id = try #require(Rig.first.console.node?.id)
		Passkey.forget(id: id)
		Rig.second.console.connect()
		#expect(await eventually { Rig.second.console.link == .locked && Rig.second.console.lock != nil } != nil)
		Rig.first.console.protect(current: "probe-pass-2", new: "")
		
		#expect(await eventually { Rig.first.console.passwordOutcome == .saved } != nil)
		#expect(await eventually(within: 10) { Rig.second.console.link.isConnected && Rig.second.shows.isLoaded } != nil)
		#expect(await eventually { Rig.both.allSatisfy { $0.console.node?.hasPassword == false } } != nil)
		#expect(Passkey.stored(id: id) == nil)
		#expect(await NodeStore().show(Rig.original, at: Rig.endpoint) != nil)
		
		guard let key = Rig.key, let nonce = Rig.first.console.node?.nonce else { return }
		Rig.first.console.send(.password(old: nil, new: key, nonce: nonce))
		#expect(await eventually { Rig.first.console.node?.hasPassword == true } != nil)
		Passkey.store(key, id: id)
	}
}

private extension JSONDecoder {
	static var iso: JSONDecoder {
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		return decoder
	}
}
