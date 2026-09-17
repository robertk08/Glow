import Foundation

struct NodeSetup: Sendable {
	struct Info: Decodable, Sendable {
		var id = ""
		var ip = ""
		var name = "Glow"
		var isProvisioned = false
		var didRefuse = false
		
		private enum CodingKeys: String, CodingKey { case id, ip, name, state, join }
		
		init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
			ip = try container.decodeIfPresent(String.self, forKey: .ip) ?? ""
			name = try container.decode(String.self, forKey: .name)
			isProvisioned = (try container.decode(String.self, forKey: .state)) == "provisioned"
			didRefuse = (try container.decodeIfPresent(String.self, forKey: .join)) == "failed"
		}
	}
	
	struct Network: Decodable, Sendable, Identifiable, Hashable {
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
	
	func scan() async throws -> [Network] {
		struct Response: Decodable { var networks: [Network] }
		let response: Response = try await get("/api/scan")
		return response.networks.sorted { $0.rssi > $1.rssi }
	}
	
	func join(ssid: String, user: String, password: String) async throws {
		try await post("/api/provision", ["ssid": ssid, "user": user, "password": password])
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
		guard let decoded = try? JSONDecoder().decode(T.self, from: data) else {
			throw Failure.unreachable
		}
		return decoded
	}
	
	private func post(_ path: String, _ body: [String: String]) async throws {
		var request = URLRequest(url: try url(path))
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = try? JSONEncoder().encode(body)
		
		let (data, _) = try await perform(request)
		
		struct Ack: Decodable { var ok: Bool; var error: String? }
		guard let ack = try? JSONDecoder().decode(Ack.self, from: data) else { throw Failure.unreachable }
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
