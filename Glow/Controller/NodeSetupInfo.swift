import Foundation

struct NodeSetupInfo: Decodable, Sendable {
	var id = ""
	var ip = ""
	var name = "Glow"
	var isProvisioned = false
	var didRefuse = false
	var isJoining = false
	var ssid = ""
	
	private enum CodingKeys: String, CodingKey { case id, ip, name, state, join, ssid }
	
	func hasJoined(ssid: String) -> Bool {
		isProvisioned && !isJoining && !didRefuse && (self.ssid.isEmpty || self.ssid == ssid)
	}
	
	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
		ip = try container.decodeIfPresent(String.self, forKey: .ip) ?? ""
		name = try container.decode(String.self, forKey: .name)
		isProvisioned = (try container.decode(String.self, forKey: .state)) == "provisioned"
		let join = try container.decodeIfPresent(String.self, forKey: .join)
		didRefuse = join == "failed"
		isJoining = join == "trying"
		ssid = try container.decodeIfPresent(String.self, forKey: .ssid) ?? ""
	}
}
