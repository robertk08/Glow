import Foundation

/// Talks to a node that is not on the network yet.
///
/// Plain HTTP against the node's setup access point, per docs/PROTOCOL.md.
/// Separate from ``ControllerLink`` on purpose: this speaks to a device that
/// has no name, no address anyone chose, and no idea what network it is going
/// to end up on.
nonisolated struct ProvisioningClient: Sendable {
    nonisolated struct Info: Decodable, Sendable {
        var firmware: String
        var id: String
        var name: String
        var isProvisioned: Bool

        private enum CodingKeys: String, CodingKey { case fw, id, name, state }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            firmware = try container.decodeIfPresent(String.self, forKey: .fw) ?? "unknown"
            id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Glow node"
            isProvisioned = (try container.decodeIfPresent(String.self, forKey: .state)) == "provisioned"
        }
    }

    nonisolated struct Network: Decodable, Sendable, Identifiable, Hashable {
        var ssid: String
        var rssi: Int
        var secure: Bool
        var channel: Int?

        var id: String { ssid }

        /// Nought to three bars, the way every other WiFi list does it.
        var bars: Int {
            switch rssi {
            case (-60)...: 3
            case (-70)..<(-60): 2
            case (-80)..<(-70): 1
            default: 0
            }
        }
    }

    nonisolated enum Failure: LocalizedError, Sendable {
        case unreachable
        case rejected(String)
        case malformed

        var errorDescription: String? {
            switch self {
            case .unreachable:
                "Couldn't reach the node. Check that you're connected to its “Glow Setup” network."
            case let .rejected(reason):
                reason
            case .malformed:
                "The node replied with something this version of Glow doesn't understand."
            }
        }
    }

    var host: String = "192.168.4.1"

    private var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20 // a WiFi scan is not instant
        configuration.waitsForConnectivity = false
        // The setup AP has no route to anywhere, so the phone must not decide
        // this request belongs on cellular.
        configuration.allowsCellularAccess = false
        return URLSession(configuration: configuration)
    }

    func info() async throws -> Info {
        try await get("/api/info")
    }

    func scan() async throws -> [Network] {
        nonisolated struct Response: Decodable { var networks: [Network] }
        let response: Response = try await get("/api/scan")
        return response.networks.sorted { $0.rssi > $1.rssi }
    }

    /// Hands over credentials. Returns when the node has accepted them, which
    /// is *before* it has joined — see PROTOCOL.md. Confirm success by finding
    /// the node again over Bonjour.
    func provision(ssid: String, password: String) async throws {
        try await post("/api/provision", body: ["ssid": ssid, "password": password])
    }

    func forget() async throws {
        try await post("/api/forget", body: [:])
    }

    // MARK: - Transport

    private func url(_ path: String) throws -> URL {
        guard let url = URL(string: "http://\(host)\(path)") else { throw Failure.unreachable }
        return url
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let (data, _) = try await perform(URLRequest(url: try url(path)))
        guard let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            throw Failure.malformed
        }
        return decoded
    }

    private func post(_ path: String, body: [String: String]) async throws {
        var request = URLRequest(url: try url(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(body)

        let (data, _) = try await perform(request)

        nonisolated struct Ack: Decodable { var ok: Bool; var error: String? }
        guard let ack = try? JSONDecoder().decode(Ack.self, from: data) else { throw Failure.malformed }
        guard ack.ok else { throw Failure.rejected(ack.error ?? "The node turned down those details.") }
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw Failure.unreachable
        }
    }
}
