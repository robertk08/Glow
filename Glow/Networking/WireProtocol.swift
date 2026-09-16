import Foundation

/// Encoding and decoding for the Glow wire protocol. See docs/PROTOCOL.md.
///
/// DMX travels as binary because a full universe update is 512 bytes raw and
/// about 700 base64-encoded, and at 40 Hz on a 2.4 GHz link that difference is
/// not academic. Everything else is JSON, where legibility is worth more than
/// bytes.
nonisolated enum Wire {
    static let version = 1
    static let dmxOpcode: UInt8 = 0x01

    /// A partial universe update: `values` written to consecutive addresses
    /// starting at `start`.
    nonisolated struct DMXFrame: Sendable, Equatable {
        var start: DMXAddress
        var values: [UInt8]

        var data: Data {
            var data = Data(capacity: values.count + 6)
            data.append(Wire.dmxOpcode)
            data.append(0) // universe 0; the byte exists so a second one is not a break
            data.append(UInt8(start.rawValue & 0xFF))
            data.append(UInt8((start.rawValue >> 8) & 0xFF))
            data.append(UInt8(values.count & 0xFF))
            data.append(UInt8((values.count >> 8) & 0xFF))
            data.append(contentsOf: values)
            return data
        }
    }

    // MARK: - App to node

    nonisolated enum ClientMessage: Encodable, Sendable {
        case hello(client: String, version: Int)
        case ping(seq: Int)
        case blackout(on: Bool)
        case refresh(hz: Int)
        case identify

        private enum CodingKeys: String, CodingKey {
            case t, client, version, seq, on, hz
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .hello(client, version):
                try container.encode("hello", forKey: .t)
                try container.encode(client, forKey: .client)
                try container.encode(version, forKey: .version)
            case let .ping(seq):
                try container.encode("ping", forKey: .t)
                try container.encode(seq, forKey: .seq)
            case let .blackout(on):
                try container.encode("blackout", forKey: .t)
                try container.encode(on, forKey: .on)
            case let .refresh(hz):
                try container.encode("refresh", forKey: .t)
                try container.encode(hz, forKey: .hz)
            case .identify:
                try container.encode("identify", forKey: .t)
            }
        }

        var jsonData: Data? { try? JSONEncoder().encode(self) }
    }

    // MARK: - Node to app

    nonisolated struct NodeStatus: Decodable, Sendable, Equatable {
        var firmware: String
        var id: String
        var name: String
        var hz: Int
        var blackout: Bool
        var uptime: Int

        private enum CodingKeys: String, CodingKey {
            case fw, id, name, hz, blackout, uptime
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            firmware = try container.decodeIfPresent(String.self, forKey: .fw) ?? "unknown"
            id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Glow node"
            hz = try container.decodeIfPresent(Int.self, forKey: .hz) ?? 40
            blackout = try container.decodeIfPresent(Bool.self, forKey: .blackout) ?? false
            uptime = try container.decodeIfPresent(Int.self, forKey: .uptime) ?? 0
        }
    }

    nonisolated enum NodeMessage: Sendable {
        case status(NodeStatus)
        case pong(seq: Int)
        case error(code: String, message: String)

        /// Unknown message types decode to `nil` rather than throwing. A node
        /// running newer firmware than the app must not break the app.
        static func decode(_ data: Data) -> NodeMessage? {
            struct Envelope: Decodable {
                var t: String
                var seq: Int?
                var code: String?
                var message: String?
            }
            guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
                return nil
            }
            switch envelope.t {
            case "status":
                guard let status = try? JSONDecoder().decode(NodeStatus.self, from: data) else {
                    return nil
                }
                return .status(status)
            case "pong":
                return .pong(seq: envelope.seq ?? 0)
            case "error":
                return .error(code: envelope.code ?? "unknown", message: envelope.message ?? "")
            default:
                return nil
            }
        }
    }
}
