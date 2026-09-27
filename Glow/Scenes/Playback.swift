import Foundation

nonisolated struct Playback: Sendable, Equatable {
	nonisolated struct Playing: Sendable, Equatable {
		var scene: String
		var cue: String
	}
	
	private(set) var playing: [Playing] = []
	var held: [Int: UInt8] = [:]
	
	init() {}
	
	init?(_ data: Data) {
		var reader = ByteReader(data)
		guard let count = reader.number() else { return nil }
		
		for _ in 0..<count {
			guard let (_, scene) = reader.identifier(), let (_, cue) = reader.identifier() else { return nil }
			playing.append(Playing(scene: scene, cue: cue))
		}
		
		while !reader.isAtEnd {
			guard let address = reader.number(), let value = reader.byte() else { return nil }
			held[address] = value
		}
	}
	
	var data: Data {
		var writer = ByteWriter()
		writer.number(playing.count)
		
		for entry in playing {
			writer.identifier(entry.scene, tag: 0)
			writer.identifier(entry.cue, tag: 0)
		}
		
		for address in held.keys.sorted() {
			writer.number(address)
			writer.byte(held[address] ?? 0)
		}
		
		return writer.data
	}
	
	func cue(of scene: String) -> String? {
		playing.first { $0.scene == scene }?.cue
	}
	
	mutating func play(_ cue: String, of scene: String) {
		playing.removeAll { $0.scene == scene }
		playing.append(Playing(scene: scene, cue: cue))
	}
	
	mutating func stop(_ scene: String) {
		playing.removeAll { $0.scene == scene }
	}
}
