import Foundation

nonisolated struct FrameStream: Sendable {
	private var last: [UInt8] = []
	private var needsEverything = true
	private var reach = Universe.channelCount
	
	mutating func cover(_ slots: Int) {
		guard slots != reach else { return }
		reach = slots
		needsEverything = true
	}
	
	mutating func startOver() {
		needsEverything = true
	}
	
	mutating func adopt(_ whole: [UInt8], start: DMXAddress, count: Int) {
		let frame = Array(whole.prefix(reach))
		let first = start.value - 1
		let end = min(first + count, frame.count)
		
		guard !needsEverything, last.count == frame.count else {
			guard first == 0, end == frame.count else { return }
			last = frame
			needsEverything = false
			return
		}
		
		for index in first..<max(first, end) {
			last[index] = frame[index]
		}
	}
	
	mutating func next(_ whole: [UInt8]) -> (start: DMXAddress, values: [UInt8])? {
		let frame = Array(whole.prefix(reach))
		defer { last = frame }
		
		guard !needsEverything, last.count == frame.count else {
			needsEverything = false
			return (DMXAddress(1)!, frame)
		}
		
		var first: Int?
		var end = 0
		
		for index in frame.indices where last[index] != frame[index] {
			if first == nil { first = index }
			end = index
		}
		
		guard let first, let start = DMXAddress(first + 1) else { return nil }
		return (start, Array(frame[first...end]))
	}
}
