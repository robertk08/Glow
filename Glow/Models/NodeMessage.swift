import Foundation

nonisolated enum Wire {
    static let version = 1
    static let dmxOpcode: UInt8 = 0x01
    
    static func frame(start: DMXAddress, values: [UInt8]) -> Data {
        var data = Data(capacity: values.count + 6)
        data.append(dmxOpcode)
        data.append(0)
        data.append(UInt8(start.value & 0xFF))
        data.append(UInt8((start.value >> 8) & 0xFF))
        data.append(UInt8(values.count & 0xFF))
        data.append(UInt8((values.count >> 8) & 0xFF))
        data.append(contentsOf: values)
        return data
    }
    
    nonisolated enum Command: Encodable, Sendable {
        case hello
        case ping(seq: Int)
        case blackout(Bool)
        case identify
        
        private enum CodingKeys: String, CodingKey { case t, client, version, seq, on }
        
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .hello:
                try container.encode("hello", forKey: .t)
                try container.encode("Glow iOS", forKey: .client)
                try container.encode(Wire.version, forKey: .version)
            case let .ping(seq):
                try container.encode("ping", forKey: .t)
                try container.encode(seq, forKey: .seq)
            case let .blackout(on):
                try container.encode("blackout", forKey: .t)
                try container.encode(on, forKey: .on)
            case .identify:
                try container.encode("identify", forKey: .t)
            }
        }
        
        var json: String? {
            guard let data = try? JSONEncoder().encode(self) else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }
    
    nonisolated struct NodeInfo: Decodable, Sendable, Equatable {
        var firmware = "unknown"
        var id = ""
        var name = "Glow"
        var uptime = 0
        
        private enum CodingKeys: String, CodingKey { case fw, id, name, uptime }
        
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            firmware = try container.decodeIfPresent(String.self, forKey: .fw) ?? "unknown"
            id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Glow"
            uptime = try container.decodeIfPresent(Int.self, forKey: .uptime) ?? 0
        }
    }
    
    nonisolated enum Reply: Sendable {
        case status(NodeInfo)
        case pong(seq: Int)
        
        static func decode(_ data: Data) -> Reply? {
            struct Envelope: Decodable { var t: String; var seq: Int? }
            guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { return nil }
            switch envelope.t {
            case "status":
                guard let info = try? JSONDecoder().decode(NodeInfo.self, from: data) else { return nil }
                return .status(info)
            case "pong":
                return .pong(seq: envelope.seq ?? 0)
            default:
                return nil
            }
        }
    }
}

nonisolated struct NodeEndpoint: Sendable, Hashable, Codable, Identifiable {
    var host: String
    var port = 80
    var name: String
    var nodeID: String?
    
    var id: String { "\(host):\(port)" }
    
    var socketURL: URL? {
        var components = URLComponents()
        components.scheme = "ws"
        components.host = host
        components.port = port == 80 ? nil : port
        components.path = "/ws"
        return components.url
    }
    
    static let fallback = NodeEndpoint(host: "glow.local", name: "glow.local")
    
    init(host: String, port: Int = 80, name: String, nodeID: String? = nil) {
        self.host = host
        self.port = port
        self.name = name
        self.nodeID = nodeID
    }
    
    init?(entry: String) {
        let trimmed = entry.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        
        if let separator = trimmed.lastIndex(of: ":"), let parsed = Int(trimmed[trimmed.index(after: separator)...]), (1...65535).contains(parsed) {
            host = String(trimmed[..<separator])
            port = parsed
        } else {
            host = trimmed
            port = 80
        }
        
        name = trimmed
    }
}
