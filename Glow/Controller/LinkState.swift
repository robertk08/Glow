import SwiftUI

nonisolated enum LinkState: Sendable, Equatable {
	case offline
	case connecting
	case connected
	case locked
	case full
	case retrying(seconds: Int)
	
	var isConnected: Bool { self == .connected }
	
	var name: String {
		switch self {
		case .offline: "Not connected"
		case .connecting: "Connecting"
		case .connected: "Connected"
		case .locked: "Locked"
		case .full: "Controller full, waiting for a device to leave"
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
		case .locked: "lock.fill"
		case .full: "person.3.fill"
		case .retrying: "wifi.exclamationmark"
		}
	}
	
	var tint: Color {
		switch self {
		case .offline: .secondary
		case .connecting: .orange
		case .connected: .green
		case .locked: .orange
		case .full: .orange
		case .retrying: .orange
		}
	}
}
