import Foundation

nonisolated enum Wire {
	static let version = 2
	static let outputOpcode: UInt8 = 0x01
	static let sourceOpcode: UInt8 = 0x02
	
	static func frame(_ opcode: UInt8, start: DMXAddress, values: [UInt8]) -> Data {
		var data = Data(capacity: values.count + 6)
		data.append(opcode)
		data.append(0)
		data.append(UInt8(start.value & 0xFF))
		data.append(UInt8((start.value >> 8) & 0xFF))
		data.append(UInt8(values.count & 0xFF))
		data.append(UInt8((values.count >> 8) & 0xFF))
		data.append(contentsOf: values)
		return data
	}
	
	static func decode(frame data: Data) -> (start: DMXAddress, values: [UInt8])? {
		let bytes = [UInt8](data)
		guard bytes.count > 6, bytes[0] == sourceOpcode, bytes[1] == 0 else { return nil }
		
		let start = Int(bytes[2]) | (Int(bytes[3]) << 8)
		let length = Int(bytes[4]) | (Int(bytes[5]) << 8)
		guard bytes.count == 6 + length, let address = DMXAddress(start) else { return nil }
		
		return (address, Array(bytes[6...]))
	}
	
	nonisolated enum Command: Encodable, Sendable {
		case hello
		case ping(seq: Int)
		case blackout(Bool)
		case master(Double)
		
		private enum CodingKeys: String, CodingKey { case t, client, version, seq, on, level }
		
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
			case let .master(level):
				try container.encode("master", forKey: .t)
				try container.encode(level, forKey: .level)
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
		var hasSource = false
		
		private enum CodingKeys: String, CodingKey { case fw, id, name, src }
		
		init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			firmware = try container.decodeIfPresent(String.self, forKey: .fw) ?? "unknown"
			id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
			name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Glow"
			hasSource = try container.decodeIfPresent(Bool.self, forKey: .src) ?? false
		}
	}
	
	nonisolated enum Reply: Sendable {
		case status(NodeInfo)
		case pong(seq: Int)
		case master(Double)
		case blackout(Bool)
		
		static func decode(_ data: Data) -> Reply? {
			struct Envelope: Decodable {
				var t: String
				var seq: Int?
				var level: Double?
				var on: Bool?
			}
			
			guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { return nil }
			
			switch envelope.t {
			case "status":
				guard let info = try? JSONDecoder().decode(NodeInfo.self, from: data) else { return nil }
				return .status(info)
			case "pong":
				return .pong(seq: envelope.seq ?? 0)
			case "master":
				guard let level = envelope.level else { return nil }
				return .master(level)
			case "blackout":
				guard let on = envelope.on else { return nil }
				return .blackout(on)
			default:
				return nil
			}
		}
	}
}
