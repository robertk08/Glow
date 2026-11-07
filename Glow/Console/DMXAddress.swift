import Foundation

nonisolated struct DMXAddress: Hashable, Sendable {
	static let range = 1...512
	
	let value: Int
	
	init?(_ value: Int) {
		guard Self.range.contains(value) else { return nil }
		self.value = value
	}
	
	init(clamping value: Int) {
		self.value = min(max(value, Self.range.lowerBound), Self.range.upperBound)
	}
	
	func offset(by offset: Int) -> DMXAddress? { DMXAddress(value + offset) }
}
