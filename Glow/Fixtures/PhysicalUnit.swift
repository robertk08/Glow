import Foundation

nonisolated enum PhysicalUnit: String, Codable, Sendable {
	case percent, degrees, hertz, seconds, kelvin, rpm
	
	func label(_ value: Double) -> String {
		switch self {
		case .percent: "\(value.formatted(.number.precision(.fractionLength(0))))%"
		case .degrees: "\(value.formatted(.number.precision(.fractionLength(0))))°"
		case .hertz: "\(value.formatted(.number.precision(.fractionLength(value < 10 ? 1 : 0)))) Hz"
		case .seconds: value < 60 ? "\(value.formatted(.number.precision(.fractionLength(1)))) s" : Duration.seconds(value).formatted(.units(allowed: [.minutes, .seconds], width: .narrow))
		case .kelvin: "\(value.formatted(.number.precision(.fractionLength(0)))) K"
		case .rpm: "\(value.formatted(.number.precision(.fractionLength(0)))) rpm"
		}
	}
}
