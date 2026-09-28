import Foundation

nonisolated struct CueList: Sendable {
	let scene: String
	let tap: SceneAction
	private(set) var cues: [ShowContents.Cue]
	
	private let starts: [String: DMXAddress]
	
	private static let budget = 6000
	
	@MainActor init(_ look: Look, cues: [Cue], fixtures: [Fixture]) {
		self.init(look, cues: cues, starts: Self.starts(of: fixtures))
	}
	
	@MainActor private init(_ look: Look, cues: [Cue], starts: [String: DMXAddress]) {
		scene = look.identifier
		tap = look.tap
		self.cues = look.cues(among: cues).map(\.entry)
		self.starts = starts
	}
	
	@MainActor static func all(_ looks: [Look], cues: [Cue], fixtures: [Fixture]) -> [CueList] {
		let grouped = Dictionary(grouping: cues, by: \.lookID)
		let starts = starts(of: fixtures)
		return looks.map { CueList($0, cues: grouped[$0.identifier] ?? [], starts: starts) }
	}
	
	@MainActor private static func starts(of fixtures: [Fixture]) -> [String: DMXAddress] {
		Dictionary(fixtures.map { ($0.identifier, $0.start) }, uniquingKeysWith: { first, _ in first })
	}
	
	func index(of identifier: String?) -> Int? {
		cues.firstIndex { $0.identifier == identifier }
	}
	
	func next(after index: Int?) -> Int? {
		guard !cues.isEmpty else { return nil }
		guard let index else { return 0 }
		return (index + 1) % cues.count
	}
	
	func previous(before index: Int) -> Int? {
		guard !cues.isEmpty else { return nil }
		return (index + cues.count - 1) % cues.count
	}
	
	func title(at index: Int) -> String {
		cues[index].label.isEmpty ? "Cue \(index + 1)" : cues[index].label
	}
	
	func status(at index: Int?) -> String {
		guard !cues.isEmpty else { return "Tap to build" }
		
		guard let index else {
			if tap == .flash { return "Hold to flash" }
			if cues.count > 1 { return "\(cues.count) cues" }
			var lights = 0
			Levels.read(cues[0].levels) { _, _, _ in lights += 1 }
			return lights == 1 ? "1 light" : "\(lights) lights"
		}
		
		guard cues.count > 1 else { return "On" }
		return cues[index].label.isEmpty ? "Cue \(index + 1) of \(cues.count)" : "\(index + 1) · \(cues[index].label)"
	}
	
	func fade(of identifier: String?) -> Double {
		index(of: identifier).map { cues[$0].fade } ?? 0
	}
	
	func removing(_ identifier: String) -> CueList {
		var trimmed = self
		trimmed.cues.removeAll { $0.identifier == identifier }
		return trimmed
	}
	
	func program(from index: Int, snapping: Bool = false) -> Data {
		var changes: [[(address: Int, value: UInt8)]] = []
		var owned = [Bool](repeating: false, count: Universe.channelCount + 1)
		
		for cue in cues {
			var change: [(address: Int, value: UInt8)] = []
			
			Levels.read(cue.levels) { light, mask, values in
				guard let start = starts[light] else { return }
				
				Levels.visit(mask, values) { slot, value in
					guard let address = start.offset(by: slot - 1) else { return }
					owned[address.value] = true
					change.append((address.value, value))
				}
			}
			
			changes.append(change)
		}
		
		var order = [index]
		var loop: Int?
		var onward = false
		
		while !snapping, cues[order[order.count - 1]].follow != nil, let next = next(after: order[order.count - 1]) {
			if let seen = order.firstIndex(of: next) {
				loop = seen
				break
			}
			
			onward = order.count == 254
			guard !onward else { break }
			order.append(next)
		}
		
		var steps = Data()
		var count = 0
		var state: [Int] = []
		var folded = -1
		
		for position in order {
			if position <= folded {
				state = []
				folded = -1
			}
			
			if state.isEmpty {
				state = [Int](repeating: -1, count: Universe.channelCount + 1)
			}
			
			while folded < position {
				folded += 1
				
				for (address, value) in changes[folded] {
					state[address] = Int(value)
				}
			}
			
			let step = step(position, state: state, owned: owned, snapping: snapping)
			
			guard count == 0 || steps.count + step.count <= Self.budget else {
				loop = nil
				onward = true
				break
			}
			
			steps.append(step)
			count += 1
		}
		
		var writer = ByteWriter()
		writer.byte(UInt8(loop ?? (onward ? 0xFE : 0xFF)))
		writer.byte(UInt8(count))
		return writer.data + steps
	}
	
	private func step(_ position: Int, state: [Int], owned: [Bool], snapping: Bool) -> Data {
		let cue = cues[position]
		var runs = ByteWriter()
		var address = 1
		
		while address <= Universe.channelCount {
			guard owned[address] else {
				address += 1
				continue
			}
			
			let start = address
			let isHeld = state[address] < 0
			var values: [UInt8] = []
			
			while address <= Universe.channelCount, owned[address], (state[address] < 0) == isHeld {
				if !isHeld { values.append(UInt8(state[address])) }
				address += 1
			}
			
			runs.word(start | (isHeld ? 0x8000 : 0))
			runs.word(address - start)
			runs.bytes(values)
		}
		
		var writer = ByteWriter()
		writer.text(cue.identifier)
		writer.number(snapping ? 0 : Self.milliseconds(cue.delay))
		writer.number(snapping ? 0 : Self.milliseconds(cue.fade))
		writer.number(snapping ? 0 : cue.follow.map { Self.milliseconds($0) + 1 } ?? 0)
		writer.number(runs.data.count)
		return writer.data + runs.data
	}
	
	static func milliseconds(_ seconds: Double) -> Int {
		max(0, Int((seconds * 1000).rounded()))
	}
}
