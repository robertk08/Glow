import Foundation

nonisolated struct Ramp: Sendable, Equatable {
	nonisolated enum Kind: Sendable, Equatable {
		case fade
		case snap
		case band(from: UInt8, to: UInt8, open: UInt8?)
	}
	
	let address: DMXAddress
	var fine: DMXAddress?
	let target: Int
	let kind: Kind
	
	func value(from start: Int, at progress: Double) -> Int {
		guard progress < 1 else { return target }
		
		switch kind {
		case .snap:
			return target
		case .fade:
			return start + Int((Double(target - start) * progress).rounded())
		case let .band(from, to, open):
			guard let low = level(start, from: from, to: to, open: open), let high = level(target, from: from, to: to, open: open) else { return target }
			let wanted = low + (high - low) * progress
			guard wanted > 0 else { return 0 }
			return Int(from) + Int((Double(to - from) * wanted).rounded())
		}
	}
	
	func level(in universe: Universe) -> Int {
		guard let fine else { return Int(universe[address]) }
		return Int(universe[address]) * 256 + Int(universe[fine])
	}
	
	func write(_ value: Int, into universe: inout Universe) {
		guard let fine else {
			universe[address] = UInt8(min(max(value, 0), 255))
			return
		}
		
		let clamped = min(max(value, 0), 65535)
		universe[address] = UInt8(clamped >> 8)
		universe[fine] = UInt8(clamped & 0xFF)
	}
	
	private func level(_ value: Int, from: UInt8, to: UInt8, open: UInt8?) -> Double? {
		if value < Int(from) { return 0 }
		if value >= Int(from), value <= Int(to) { return Double(value - Int(from)) / Double(max(1, Int(to) - Int(from))) }
		if let open, value >= Int(open) { return 1 }
		return nil
	}
}
