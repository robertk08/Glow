import Foundation

nonisolated struct FrameStream: Sendable {
	typealias Run = (start: DMXAddress, values: [UInt8])
	
	private(set) var sent = 0
	private var last: [UInt8] = []
	private var written = [Int](repeating: 0, count: Universe.channelCount)
	private var reach = Universe.channelCount
	
	mutating func cover(_ slots: Int) {
		reach = slots
	}
	
	mutating func startOver() {
		sent = 0
		last = []
		written = [Int](repeating: 0, count: Universe.channelCount)
	}
	
	mutating func adopt(_ runs: [Run], ack: Int, into universe: inout Universe) {
		let acked = sent - Int(UInt16(truncatingIfNeeded: sent - ack))
		
		for run in runs {
			for (offset, value) in run.values.enumerated() {
				let index = run.start.value - 1 + offset
				guard written[index] <= acked, let address = run.start.offset(by: offset) else { continue }
				universe[address] = value
				if !last.isEmpty { last[index] = value }
			}
		}
		
		guard last.isEmpty, runs.count == 1, runs[0].start.value == 1, runs[0].values.count == Universe.channelCount else { return }
		last = universe.values
	}
	
	mutating func next(_ whole: [UInt8]) -> [Run] {
		guard !last.isEmpty else {
			last = whole
			sent += 1
			written = [Int](repeating: sent, count: Universe.channelCount)
			return [(DMXAddress(1)!, Array(whole.prefix(reach)))]
		}
		
		let runs = Self.changes(from: last, to: whole)
		guard !runs.isEmpty else { return [] }
		sent += 1
		
		for run in runs {
			for offset in run.values.indices {
				last[run.start.value - 1 + offset] = run.values[offset]
				written[run.start.value - 1 + offset] = sent
			}
		}
		
		return runs
	}
	
	static func changes(from old: some RandomAccessCollection<UInt8>, to new: [UInt8]) -> [Run] {
		var runs: [Run] = []
		var index = 0
		var before = old.startIndex
		
		while index < new.count {
			guard new[index] != old[before] else {
				index += 1
				before = old.index(after: before)
				continue
			}
			
			let first = index
			
			while index < new.count, new[index] != old[before] {
				index += 1
				before = old.index(after: before)
			}
			
			runs.append((DMXAddress(first + 1)!, Array(new[first..<index])))
		}
		
		return runs
	}
}
