import Foundation

enum LinkEvent: Sendable {
	case state(LinkState)
	case status(Wire.NodeInfo)
	case latency(TimeInterval)
	case frame(start: DMXAddress, values: [UInt8])
	case master(Double)
	case blackout(Bool)
}
