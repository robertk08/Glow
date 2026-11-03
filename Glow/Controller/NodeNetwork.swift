import Foundation

struct NodeNetwork: Decodable, Sendable, Identifiable, Hashable {
	var ssid: String
	var rssi: Int
	var secure: Bool
	var enterprise: Bool
	
	var id: String { ssid }
	var bars: Int {
		switch rssi {
		case (-60)...: 3
		case (-70)..<(-60): 2
		case (-80)..<(-70): 1
		default: 0
		}
	}
}
