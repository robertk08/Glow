import Foundation

nonisolated struct FrameStream: Sendable {
	private var last: [UInt8] = []
	private var reach = Universe.channelCount
	
	mutating func cover(_ slots: Int) {
		reach = slots
	}
	
	mutating func startOver() {
		last = []
	}
	
	mutating func adopt(_ values: [UInt8], at start: DMXAddress, into whole: [UInt8]) {
		if last.isEmpty, start.value == 1, values.count == Universe.channelCount {
			last = whole
			return
		}
		
		guard !last.isEmpty else { return }
		
		for (offset, value) in values.enumerated() where start.value - 1 + offset < last.count {
			last[start.value - 1 + offset] = value
		}
	}
	
	mutating func next(_ whole: [UInt8]) -> [(start: DMXAddress, values: [UInt8])] {
		guard !last.isEmpty else {
			last = whole
			return [(DMXAddress(1)!, Array(whole.prefix(reach)))]
		}
		
		var runs: [(start: DMXAddress, values: [UInt8])] = []
		var index = 0
		
		while index < whole.count {
			guard whole[index] != last[index] else {
				index += 1
				continue
			}
			
			let first = index
			
			while index < whole.count, whole[index] != last[index] {
				last[index] = whole[index]
				index += 1
			}
			
			runs.append((DMXAddress(first + 1)!, Array(whole[first..<index])))
		}
		
		return runs
	}
}
