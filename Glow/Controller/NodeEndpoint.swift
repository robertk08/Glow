import Foundation

nonisolated struct NodeEndpoint: Sendable, Hashable, Codable, Identifiable {
	var host: String
	var port = 80
	var name: String
	var nodeID: String?
	
	var id: String { nodeID ?? "\(host):\(port)" }
	
	var socketURL: URL? {
		var components = URLComponents()
		components.scheme = "ws"
		components.host = host
		components.port = port == 80 ? nil : port
		components.path = "/ws"
		return components.url
	}
	
	func apiURL(path: String) -> URL? {
		var components = URLComponents()
		components.scheme = "http"
		components.host = host
		components.port = port == 80 ? nil : port
		components.path = "/api/\(path)"
		return components.url
	}
	
	static let fallback = NodeEndpoint(host: "glow.local", name: "glow.local")
	static let setup = NodeEndpoint(host: "192.168.4.1", name: "Glow Setup")
	
	init(host: String, port: Int = 80, name: String, nodeID: String? = nil) {
		self.host = host
		self.port = port
		self.name = name
		self.nodeID = nodeID
	}
}
