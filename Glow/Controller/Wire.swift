import Foundation

nonisolated enum Wire {
	static let version = 2
	static let outputOpcode: UInt8 = 0x01
	static let sourceOpcode: UInt8 = 0x02
	static let documentOpcode: UInt8 = 0x03
	static let documentHeader = 7
	
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
		case span(Int)
		case scene(String)
		
		private enum CodingKeys: String, CodingKey { case t, client, version, seq, on, level, slots, id }
		
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
			case let .span(slots):
				try container.encode("span", forKey: .t)
				try container.encode(slots, forKey: .slots)
			case let .scene(identifier):
				try container.encode("scene", forKey: .t)
				try container.encode(identifier, forKey: .id)
			}
		}
		
		var message: URLSessionWebSocketTask.Message {
			.string(String(decoding: (try? JSONEncoder().encode(self)) ?? Data(), as: UTF8.self))
		}
	}
	
	nonisolated struct NodeInfo: Decodable, Sendable, Equatable {
		var firmware = "unknown"
		var id = ""
		var name = "Glow"
		var hasSource = false
		var client: Int?
		var address = ""
		var scene = ""
		var master = 1.0
		var blackout = false
		
		private enum CodingKeys: String, CodingKey { case fw, id, name, src, client, ip, scene, master, blackout }
		
		init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			firmware = try container.decodeIfPresent(String.self, forKey: .fw) ?? "unknown"
			id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
			name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Glow"
			hasSource = try container.decodeIfPresent(Bool.self, forKey: .src) ?? false
			client = try container.decodeIfPresent(Int.self, forKey: .client)
			address = try container.decodeIfPresent(String.self, forKey: .ip) ?? ""
			scene = try container.decodeIfPresent(String.self, forKey: .scene) ?? ""
			master = try container.decodeIfPresent(Double.self, forKey: .master) ?? 1
			blackout = try container.decodeIfPresent(Bool.self, forKey: .blackout) ?? false
		}
	}
	
	nonisolated struct Notice: Sendable, Equatable {
		var show: String?
		var folder: String?
		var id: String?
		var isDelete = false
		var body: Data?
		var landed: Bool?
	}
	
	static func document(show: String, folder: String, id: String, body: Data?) -> Data {
		let name = Array(show.utf8)
		let place = Array(folder.utf8)
		let key = Array(id.utf8)
		let payload = body ?? Data()
		
		var data = Data(capacity: documentHeader + name.count + place.count + key.count + payload.count)
		data.append(documentOpcode)
		data.append(body == nil ? 1 : 0)
		data.append(UInt8(name.count))
		data.append(UInt8(place.count))
		data.append(UInt8(key.count))
		data.append(UInt8(payload.count & 0xFF))
		data.append(UInt8((payload.count >> 8) & 0xFF))
		data.append(contentsOf: name)
		data.append(contentsOf: place)
		data.append(contentsOf: key)
		data.append(payload)
		return data
	}
	
	static func decode(document data: Data) -> Notice? {
		let bytes = [UInt8](data)
		guard bytes.count >= documentHeader, bytes[0] == documentOpcode else { return nil }
		
		let showLength = Int(bytes[2])
		let folderLength = Int(bytes[3])
		let idLength = Int(bytes[4])
		let bodyLength = Int(bytes[5]) | (Int(bytes[6]) << 8)
		guard bytes.count == documentHeader + showLength + folderLength + idLength + bodyLength else { return nil }
		
		var cursor = documentHeader
		let show = String(decoding: bytes[cursor..<(cursor + showLength)], as: UTF8.self)
		cursor += showLength
		let folder = String(decoding: bytes[cursor..<(cursor + folderLength)], as: UTF8.self)
		cursor += folderLength
		let id = String(decoding: bytes[cursor..<(cursor + idLength)], as: UTF8.self)
		cursor += idLength
		
		let isDelete = bytes[1] == 1
		var notice = Notice(show: show, folder: folder, id: id, isDelete: isDelete)
		if !isDelete { notice.body = Data(bytes[cursor..<(cursor + bodyLength)]) }
		return notice
	}
	
	nonisolated enum Reply: Sendable {
		case status(NodeInfo)
		case pong(seq: Int)
		case master(Double)
		case blackout(Bool)
		case scene(String)
		case notice(Notice)
		
		static func decode(_ data: Data) -> Reply? {
			struct Envelope: Decodable {
				var t: String
				var seq: Int?
				var level: Double?
				var on: Bool?
				var show: String?
				var folder: String?
				var id: String?
				var op: String?
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
			case "scene":
				guard let identifier = envelope.id else { return nil }
				return .scene(identifier)
			case "shows":
				return .notice(Notice())
			case "wrote", "unwritten":
				guard let show = envelope.show, let folder = envelope.folder, let id = envelope.id else { return nil }
				return .notice(Notice(show: show, folder: folder, id: id, landed: envelope.t == "wrote"))
			case "doc":
				guard let show = envelope.show, let folder = envelope.folder, let id = envelope.id else { return nil }
				return .notice(Notice(show: show, folder: folder, id: id, isDelete: envelope.op == "delete"))
			default:
				return nil
			}
		}
	}
}
