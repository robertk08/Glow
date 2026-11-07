import Foundation

nonisolated struct NodeEndpoint: Sendable, Equatable, Codable {
	var host: String
	var session: String?
	
	static let fallback = NodeEndpoint(host: "glow.local")
	static let setup = NodeEndpoint(host: "192.168.4.1")
	
	func url(scheme: String, path: String) -> URL? {
		var components = URLComponents()
		components.scheme = scheme
		components.host = host
		components.path = path
		return components.url
	}
}
