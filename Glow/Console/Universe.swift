import Foundation

nonisolated struct Universe: Sendable, Equatable {
	static let channelCount = 512
	static let minimumSlots = 24
	
	private(set) var values = [UInt8](repeating: 0, count: Universe.channelCount)
	
	subscript(address: DMXAddress) -> UInt8 {
		get { values[address.value - 1] }
		set { values[address.value - 1] = newValue }
	}
	
	mutating func set(_ newValues: [UInt8], at address: DMXAddress) {
		for (offset, value) in newValues.enumerated() {
			guard let target = address.offset(by: offset) else { return }
			self[target] = value
		}
	}
}
