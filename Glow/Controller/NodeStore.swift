import Foundation

actor NodeStore {
	enum Folder: String, Sendable, CaseIterable {
		case lights, groups, made, scenes
	}
	
	enum Listing: Sendable {
		case list(ShowList)
		case blank
		case unreachable
	}
	
	enum Failure: LocalizedError, Sendable {
		case unreachable
		case refused
		
		var errorDescription: String? {
			switch self {
			case .unreachable: "Couldn't reach the node."
			case .refused: "The node turned those details down."
			}
		}
	}
	
	nonisolated struct Setup: Decodable, Sendable {
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
	
	private enum Answer: Sendable {
		case body(Data)
		case missing
		case refused
		case failed
		
		var isWritten: Bool {
			if case .body = self { return true }
			return false
		}
	}
	
	private let session: URLSession
	private let decoder = JSONDecoder()
	private let encoder = JSONEncoder()
	
	init() {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.waitsForConnectivity = false
		configuration.timeoutIntervalForRequest = 8
		configuration.allowsCellularAccess = false
		session = URLSession(configuration: configuration)
		decoder.dateDecodingStrategy = .iso8601
		encoder.dateEncodingStrategy = .iso8601
	}
	
	func shows(at endpoint: NodeEndpoint) async -> Listing {
		switch await send(endpoint, "shows", method: "GET", body: nil, client: nil) {
		case let .body(data):
			guard let list = try? decoder.decode(ShowList.self, from: data), !list.shows.isEmpty else { return .blank }
			return .list(list)
		case .missing: return .blank
		case .refused, .failed: return .unreachable
		}
	}
	
	func setup(at endpoint: NodeEndpoint) async -> Setup? {
		guard case let .body(data) = await send(endpoint, "info", method: "GET", body: nil, client: nil) else { return nil }
		return try? decoder.decode(Setup.self, from: data)
	}
	
	func networks(at endpoint: NodeEndpoint) async -> [NodeNetwork]? {
		struct Scan: Decodable {
			var networks: [NodeNetwork]
		}
		
		guard case let .body(data) = await send(endpoint, "scan", method: "GET", body: nil, client: nil), let scan = try? decoder.decode(Scan.self, from: data) else { return nil }
		return scan.networks.sorted { $0.rssi > $1.rssi }
	}
	
	func command(_ path: String, at endpoint: NodeEndpoint, fields: [String: String] = [:]) async throws {
		switch await send(endpoint, path, method: "POST", body: try? encoder.encode(fields), client: nil) {
		case .body: return
		case .missing, .refused: throw Failure.refused
		case .failed: throw Failure.unreachable
		}
	}
	
	func save(_ list: ShowList, at endpoint: NodeEndpoint, client: Int?) async -> Bool {
		guard let body = try? encoder.encode(list) else { return false }
		return await send(endpoint, "shows", method: "PUT", body: body, client: client).isWritten
	}
	
	func show(_ showID: String, at endpoint: NodeEndpoint) async -> ShowContents? {
		guard case let .body(data) = await send(endpoint, "show/\(showID)", method: "GET", body: nil, client: nil) else { return nil }
		return try? decoder.decode(ShowContents.self, from: data)
	}
	
	func object(_ folder: Folder, id: String, in showID: String, at endpoint: NodeEndpoint) async -> Data? {
		guard case let .body(data) = await send(endpoint, "show/\(showID)/\(folder.rawValue)/\(id)", method: "GET", body: nil, client: nil) else { return nil }
		return data
	}
	
	func put(_ body: Data, folder: Folder, id: String, in showID: String, at endpoint: NodeEndpoint, client: Int?) async -> Bool {
		await send(endpoint, "show/\(showID)/\(folder.rawValue)/\(id)", method: "PUT", body: body, client: client).isWritten
	}
	
	func delete(_ folder: Folder, id: String, in showID: String, at endpoint: NodeEndpoint, client: Int?) async -> Bool {
		await send(endpoint, "show/\(showID)/\(folder.rawValue)/\(id)", method: "DELETE", body: nil, client: client).isWritten
	}
	
	func deleteShow(_ showID: String, at endpoint: NodeEndpoint, client: Int?) async -> Bool {
		await send(endpoint, "show/\(showID)", method: "DELETE", body: nil, client: client).isWritten
	}
	
	private func send(_ endpoint: NodeEndpoint, _ path: String, method: String, body: Data?, client: Int?) async -> Answer {
		guard let url = endpoint.apiURL(path: path) else { return .failed }
		
		var request = URLRequest(url: url)
		request.httpMethod = method
		request.httpBody = body
		if let client { request.setValue("\(client)", forHTTPHeaderField: "X-Glow-Client") }
		
		guard let (data, response) = try? await session.data(for: request) else { return .failed }
		guard let http = response as? HTTPURLResponse else { return .failed }
		if http.statusCode == 404 { return .missing }
		guard http.statusCode == 200 else { return .refused }
		return .body(data)
	}
}
