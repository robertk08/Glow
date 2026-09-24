import Foundation

nonisolated struct NodeEndpoint: Sendable, Hashable, Codable {
	var host: String
	var port = 80
	var nodeID: String?
	
	static let fallback = NodeEndpoint(host: "glow.local")
	static let setup = NodeEndpoint(host: "192.168.4.1")
	
	func url(scheme: String, path: String) -> URL? {
		var components = URLComponents()
		components.scheme = scheme
		components.host = host
		components.port = port == 80 ? nil : port
		components.path = path
		return components.url
	}
}
