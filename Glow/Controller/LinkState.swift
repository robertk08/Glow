import SwiftUI

enum LinkState: Sendable, Equatable {
	case offline
	case connecting
	case connected
	case retrying(seconds: Int)
	
	var isConnected: Bool { self == .connected }
	
	var name: String {
		switch self {
		case .offline: "Not connected"
		case .connecting: "Connecting"
		case .connected: "Connected"
		case let .retrying(seconds): "Reconnecting in \(seconds)s"
		}
	}
	
	func summary(latency: TimeInterval?) -> String {
		guard self == .connected, let latency else { return name }
		return "Connected · \(Int(latency * 1000)) ms"
	}
	
	var symbol: String {
		switch self {
		case .offline: "wifi.slash"
		case .connecting: "wifi"
		case .connected: "wifi"
		case .retrying: "wifi.exclamationmark"
		}
	}
	
	var tint: Color {
		switch self {
		case .offline: .secondary
		case .connecting: .orange
		case .connected: .green
		case .retrying: .orange
		}
	}
}
