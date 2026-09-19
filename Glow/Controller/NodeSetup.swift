import Foundation

struct NodeSetup: Sendable {
	var host = "192.168.4.1"
	var port = 80
	
	private var session: URLSession {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.timeoutIntervalForRequest = 5
		configuration.waitsForConnectivity = false
		configuration.allowsCellularAccess = false
		return URLSession(configuration: configuration)
	}
	
	func info() async throws -> NodeSetupInfo {
		try await get("/api/info")
	}
	
	func scan() async throws -> [NodeNetwork] {
		let response: NodeNetworkScan = try await get("/api/scan")
		return response.networks.sorted { $0.rssi > $1.rssi }
	}
	
	func join(ssid: String, user: String, password: String) async throws {
		try await post("/api/provision", ["ssid": ssid, "user": user, "password": password])
	}
	
	func begin() async throws {
		try await post("/api/setup", [:])
	}
	
	func forget() async throws {
		try await post("/api/forget", [:])
	}
	
	private func url(_ path: String) throws -> URL {
		var components = URLComponents()
		components.scheme = "http"
		components.host = host
		components.port = port == 80 ? nil : port
		components.path = path
		guard let url = components.url else { throw NodeSetupFailure.unreachable }
		return url
	}
	
	private func get<T: Decodable>(_ path: String) async throws -> T {
		let (data, _) = try await perform(URLRequest(url: try url(path)))
		guard let decoded = try? JSONDecoder().decode(T.self, from: data) else { throw NodeSetupFailure.unreachable }
		return decoded
	}
	
	private func post(_ path: String, _ body: [String: String]) async throws {
		var request = URLRequest(url: try url(path))
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = try? JSONEncoder().encode(body)
		
		let (data, _) = try await perform(request)
		
		guard let ack = try? JSONDecoder().decode(NodeSetupAcknowledgment.self, from: data) else { throw NodeSetupFailure.unreachable }
		guard ack.ok else { throw NodeSetupFailure.refused(ack.error ?? "The node turned those details down.") }
	}
	
	private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
		do {
			return try await session.data(for: request)
		} catch {
			throw NodeSetupFailure.unreachable
		}
	}
}
