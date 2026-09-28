import Foundation

nonisolated struct Playback: Sendable, Equatable {
	nonisolated struct Playing: Sendable, Equatable {
		var scene: String
		var cue: String
		var wants = false
	}
	
	private(set) var playing: [Playing] = []
	private(set) var fades: [String: Fade] = [:]
	
	init() {}
	
	init?(_ state: [UInt8], at date: Date) {
		var reader = ByteReader(Data(state))
		guard reader.byte() == Wire.commandOpcode, reader.byte() != nil, reader.word() != nil, let count = reader.number() else { return nil }
		
		for _ in 0..<count {
			guard let scene = reader.text(), let cue = reader.text(), let delay = reader.number(), let fade = reader.number(), let elapsed = reader.number(), let wants = reader.byte() else { return nil }
			playing.append(Playing(scene: scene, cue: cue, wants: wants == 1))
			let start = date.addingTimeInterval(Double(delay - elapsed) / 1000)
			if elapsed < delay + fade { fades[scene] = Fade(start: start, end: start.addingTimeInterval(Double(fade) / 1000)) }
		}
	}
	
	func cue(of scene: String) -> String? {
		playing.first { $0.scene == scene }?.cue
	}
	
	mutating func play(_ cue: String, of scene: String, fade: Fade?) {
		playing.removeAll { $0.scene == scene }
		playing.append(Playing(scene: scene, cue: cue))
		fades[scene] = fade
	}
	
	mutating func stop(_ scene: String) {
		playing.removeAll { $0.scene == scene }
		fades[scene] = nil
	}
}
