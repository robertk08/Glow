import Foundation

nonisolated enum Wire {
	static let outputOpcode: UInt8 = 0x01
	static let sourceOpcode: UInt8 = 0x02
	static let documentOpcode: UInt8 = 0x03
	static let bothOpcode: UInt8 = 0x04
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
	
	nonisolated enum Command: Sendable {
		case hello
		case ping(seq: Int)
		case blackout(Bool)
		case master(Double)
		case span(Int)
		case scene(String)
		case addShow(Show)
		case renameShow(Show)
		case removeShow(String)
		case openShow(String)
		
		var message: URLSessionWebSocketTask.Message {
			let fields: [String: Any] = switch self {
			case .hello: ["t": "hello"]
			case let .ping(seq): ["t": "ping", "seq": seq]
			case let .blackout(on): ["t": "blackout", "on": on]
			case let .master(level): ["t": "master", "level": level]
			case let .span(slots): ["t": "span", "slots": slots]
			case let .scene(identifier): ["t": "scene", "id": identifier]
			case let .addShow(show): ["t": "show.add", "id": show.id, "name": show.name]
			case let .renameShow(show): ["t": "show.rename", "id": show.id, "name": show.name]
			case let .removeShow(identifier): ["t": "show.remove", "id": identifier]
			case let .openShow(identifier): ["t": "show.open", "id": identifier]
			}
			
			return .string(String(decoding: (try? JSONSerialization.data(withJSONObject: fields)) ?? Data(), as: UTF8.self))
		}
	}
	
	nonisolated struct NodeInfo: Decodable, Sendable, Equatable {
		var firmware = "unknown"
		var hasSource = false
		var client: Int?
		var address = ""
		var scene = ""
		var master = 1.0
		var blackout = false
		
		private enum CodingKeys: String, CodingKey { case fw, src, client, ip, scene, master, blackout }
		
		init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			firmware = try container.decodeIfPresent(String.self, forKey: .fw) ?? "unknown"
			hasSource = try container.decodeIfPresent(Bool.self, forKey: .src) ?? false
			client = try container.decodeIfPresent(Int.self, forKey: .client)
			address = try container.decodeIfPresent(String.self, forKey: .ip) ?? ""
			scene = try container.decodeIfPresent(String.self, forKey: .scene) ?? ""
			master = try container.decodeIfPresent(Double.self, forKey: .master) ?? 1
			blackout = try container.decodeIfPresent(Bool.self, forKey: .blackout) ?? false
		}
	}
	
	nonisolated struct Place: Sendable, Equatable {
		var show: String
		var folder: String
		var id: String
		
		var key: String {
			"\(folder)/\(id)"
		}
	}
	
	nonisolated enum Notice: Sendable, Equatable {
		case shows(ShowList)
		case stored(Place, Data?)
		case erased(Place)
		case landed(Place, Bool)
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
	
	static func event(_ message: URLSessionWebSocketTask.Message) -> NodeLink.Event? {
		switch message {
		case let .data(data):
			let bytes = [UInt8](data)
			
			if bytes.first == documentOpcode, bytes.count >= documentHeader {
				let lengths = [Int(bytes[2]), Int(bytes[3]), Int(bytes[4]), Int(bytes[5]) | (Int(bytes[6]) << 8)]
				guard bytes.count == documentHeader + lengths.reduce(0, +) else { return nil }
				var cursor = documentHeader
				var parts: [Data] = []
				
				for length in lengths {
					parts.append(Data(bytes[cursor..<(cursor + length)]))
					cursor += length
				}
				
				let place = Place(show: String(decoding: parts[0], as: UTF8.self), folder: String(decoding: parts[1], as: UTF8.self), id: String(decoding: parts[2], as: UTF8.self))
				return .notice(bytes[1] == 1 ? .erased(place) : .stored(place, parts[3]))
			}
			
			guard bytes.count > 6, bytes[0] == sourceOpcode, bytes[1] == 0, bytes.count == 6 + (Int(bytes[4]) | (Int(bytes[5]) << 8)) else { return nil }
			guard let start = DMXAddress(Int(bytes[2]) | (Int(bytes[3]) << 8)) else { return nil }
			return .frame(start: start, values: Array(bytes[6...]))
		case let .string(text):
			struct Envelope: Decodable {
				var t: String
				var seq: Int?
				var level: Double?
				var on: Bool?
				var show: String?
				var folder: String?
				var id: String?
				var op: String?
				
				var place: Place? {
					guard let show, let folder, let id else { return nil }
					return Place(show: show, folder: folder, id: id)
				}
			}
			
			let data = Data(text.utf8)
			guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { return nil }
			
			switch envelope.t {
			case "status":
				guard let info = try? JSONDecoder().decode(NodeInfo.self, from: data) else { return nil }
				return .status(info)
			case "pong":
				return .pong(envelope.seq ?? 0)
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
				guard let list = try? JSONDecoder().decode(ShowList.self, from: data) else { return nil }
				return .notice(.shows(list))
			case "wrote", "unwritten":
				guard let place = envelope.place else { return nil }
				return .notice(.landed(place, envelope.t == "wrote"))
			case "doc":
				guard let place = envelope.place else { return nil }
				return .notice(envelope.op == "delete" ? .erased(place) : .stored(place, nil))
			default:
				return nil
			}
		@unknown default:
			return nil
		}
	}
}
