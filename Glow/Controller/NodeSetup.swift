import Foundation

struct NodeSetup: Sendable {
	struct Info: Decodable, Sendable {
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
	
	struct Scan: Decodable {
		var networks: [NodeNetwork]
	}
	
	struct Acknowledgment: Decodable {
		var ok: Bool
		var error: String?
	}
	
	enum Failure: LocalizedError, Sendable {
		case unreachable
		case refused(String)
		
		var errorDescription: String? {
			switch self {
			case .unreachable: "Couldn't reach the node."
			case let .refused(reason): reason
			}
		}
	}
	
	var host = "192.168.4.1"
	var port = 80
	
	private var session: URLSession {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.timeoutIntervalForRequest = 5
		configuration.waitsForConnectivity = false
		configuration.allowsCellularAccess = false
		return URLSession(configuration: configuration)
	}
	
	func info() async throws -> Info {
		try await get("/api/info")
	}
	
	func scan() async throws -> [NodeNetwork] {
		let response: Scan = try await get("/api/scan")
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
		guard let url = components.url else { throw Failure.unreachable }
		return url
	}
	
	private func get<T: Decodable>(_ path: String) async throws -> T {
		let (data, _) = try await perform(URLRequest(url: try url(path)))
		guard let decoded = try? JSONDecoder().decode(T.self, from: data) else { throw Failure.unreachable }
		return decoded
	}
	
	private func post(_ path: String, _ body: [String: String]) async throws {
		var request = URLRequest(url: try url(path))
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = try? JSONEncoder().encode(body)
		
		let (data, _) = try await perform(request)
		
		guard let ack = try? JSONDecoder().decode(Acknowledgment.self, from: data) else { throw Failure.unreachable }
		guard ack.ok else { throw Failure.refused(ack.error ?? "The node turned those details down.") }
	}
	
	private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
		do {
			return try await session.data(for: request)
		} catch {
			throw Failure.unreachable
		}
	}
}
