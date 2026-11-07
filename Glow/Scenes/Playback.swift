import Foundation
import Observation

@Observable
final class Playback {
	nonisolated struct Playing: Sendable, Equatable {
		var scene: String
		var cue: String
		var wants = false
		var caller = 0xFF
	}
	
	@Observable
	fileprivate final class Executor {
		var playing: Playing?
		var fade: Fade?
		var fall = 0.0
		var armed: String?
		var isFlashing = false
	}
	
	private(set) var order: [String] = []
	private var executors: [String: Executor] = [:]
	
	var playing: [Playing] {
		order.compactMap { executors[$0]?.playing }
	}
	
	func cue(of scene: String) -> String? {
		executors[scene]?.playing?.cue
	}
	
	func fade(of scene: String) -> Fade? {
		executors[scene]?.fade
	}
	
	func fall(of scene: String) -> Double {
		executors[scene]?.fall ?? 0
	}
	
	func armed(of scene: String) -> String? {
		executors[scene]?.armed
	}
	
	func isFlashing(_ scene: String) -> Bool {
		executors[scene]?.isFlashing ?? false
	}
	
	func play(_ cue: String, of scene: String, fade: Fade) {
		let executor = executor(scene)
		executor.playing = Playing(scene: scene, cue: cue)
		executor.fade = fade
		executor.isFlashing = false
		guard order.last != scene else { return }
		order.removeAll { $0 == scene }
		order.append(scene)
	}
	
	func stop(_ scene: String, fade: Double) {
		guard let executor = executors[scene] else { return }
		executor.playing = nil
		executor.fade = nil
		executor.fall = fade
		executor.isFlashing = false
		order.removeAll { $0 == scene }
	}
	
	func arm(_ cue: String?, of scene: String) {
		executor(scene).armed = cue
	}
	
	func flash(_ scene: String, _ isHeld: Bool) {
		executors[scene]?.isFlashing = isHeld
	}
	
	func adopt(_ state: [UInt8], at date: Date) -> Bool {
		var reader = ByteReader(Data(state))
		guard reader.byte() == Wire.commandOpcode, reader.byte() != nil, reader.word() != nil, let count = reader.number() else { return false }
		var fresh: [(playing: Playing, fade: Fade)] = []
		
		for _ in 0..<count {
			guard let scene = reader.text(), let cue = reader.text(), let delay = reader.number(), let fade = reader.number(), let elapsed = reader.number(), let wants = reader.byte(), let caller = reader.byte() else { return false }
			let start = date.addingTimeInterval(Double(delay - elapsed) / 1000)
			fresh.append((Playing(scene: scene, cue: cue, wants: wants == 1, caller: Int(caller)), Fade(start: start, end: start.addingTimeInterval(Double(fade) / 1000))))
		}
		
		guard fresh.map(\.playing) != playing else { return true }
		
		for (scene, executor) in executors {
			let entry = fresh.first { $0.playing.scene == scene }
			guard executor.playing != entry?.playing else { continue }
			executor.playing = entry?.playing
			executor.fade = entry?.fade
			executor.fall = 0
		}
		
		for entry in fresh where executors[entry.playing.scene] == nil {
			let executor = executor(entry.playing.scene)
			executor.playing = entry.playing
			executor.fade = entry.fade
		}
		
		order = fresh.map(\.playing.scene)
		return true
	}
	
	private func executor(_ scene: String) -> Executor {
		if let executor = executors[scene] { return executor }
		let executor = Executor()
		executors[scene] = executor
		return executor
	}
}
