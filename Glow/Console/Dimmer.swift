import Foundation

struct Dimmer: Equatable {
	enum Kind: Equatable {
		case linear
		case band(from: UInt8, to: UInt8, open: UInt8?)
	}
	
	var address: DMXAddress
	var kind: Kind
	var fineAddress: DMXAddress?
	
	func scale(_ value: UInt8, by master: Double) -> UInt8 {
		guard master < 1 else { return value }
		guard master > 0 else { return 0 }
		
		switch kind {
		case .linear: return UInt8((Double(value) * master).rounded())
		case let .band(from, to, open):
			if value < from { return value }
			if value <= to { return from + UInt8((Double(value - from) * master).rounded()) }
			if let open, value >= open { return from + UInt8((Double(to - from) * master).rounded()) }
			return value
		}
	}
}
