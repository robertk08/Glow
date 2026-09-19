import Foundation

struct NodeNetwork: Decodable, Sendable, Identifiable, Hashable {
	var ssid: String
	var rssi: Int
	var secure: Bool
	var enterprise: Bool
	
	private enum CodingKeys: String, CodingKey { case ssid, rssi, secure, enterprise }
	
	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		ssid = try container.decode(String.self, forKey: .ssid)
		rssi = try container.decode(Int.self, forKey: .rssi)
		secure = try container.decode(Bool.self, forKey: .secure)
		enterprise = try container.decodeIfPresent(Bool.self, forKey: .enterprise) ?? false
	}
	
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
