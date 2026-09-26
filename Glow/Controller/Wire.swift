import Foundation

nonisolated enum Wire {
	static let outputOpcode: UInt8 = 0x01
	static let sourceOpcode: UInt8 = 0x02
	static let documentOpcode: UInt8 = 0x03
	static let bothOpcode: UInt8 = 0x04
	static let documentHeader = 7
	static let recordHeader = 5
	
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
		case unlock(key: Data, nonce: String)
		case password(old: Data?, new: Data?, nonce: String)
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
			case let .unlock(key, nonce): ["t": "unlock", "proof": Passkey.proof("unlock", nonce: nonce, key: key)]
			case let .password(old, new, nonce): ["t": "password", "proof": Passkey.proof("change", nonce: nonce, key: old), "key": Passkey.wrap(new, nonce: nonce, key: old)]
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
		var id = ""
		var hasPassword = false
		var nonce = ""
		var session = ""
		
		var passwordAction: String {
			hasPassword ? "Change Password" : "Set Password"
		}
		
		private enum CodingKeys: String, CodingKey { case fw, src, client, ip, scene, master, blackout, id, password, nonce, session }
		
		init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			firmware = try container.decodeIfPresent(String.self, forKey: .fw) ?? "unknown"
			hasSource = try container.decodeIfPresent(Bool.self, forKey: .src) ?? false
			client = try container.decodeIfPresent(Int.self, forKey: .client)
			address = try container.decodeIfPresent(String.self, forKey: .ip) ?? ""
			scene = try container.decodeIfPresent(String.self, forKey: .scene) ?? ""
			master = try container.decodeIfPresent(Double.self, forKey: .master) ?? 1
			blackout = try container.decodeIfPresent(Bool.self, forKey: .blackout) ?? false
			id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
			hasPassword = try container.decodeIfPresent(Bool.self, forKey: .password) ?? false
			nonce = try container.decodeIfPresent(String.self, forKey: .nonce) ?? ""
			session = try container.decodeIfPresent(String.self, forKey: .session) ?? ""
		}
	}
	
	nonisolated struct Lock: Decodable, Sendable, Equatable {
		var id = ""
		var nonce = ""
		var isWrong = false
		var wait = 0
		
		var message: String {
			isWrong ? "That password is wrong." : "This controller has a password."
		}
		
		private enum CodingKeys: String, CodingKey { case id, nonce, wrong, wait }
		
		init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
			nonce = try container.decodeIfPresent(String.self, forKey: .nonce) ?? ""
			isWrong = try container.decodeIfPresent(Bool.self, forKey: .wrong) ?? false
			wait = try container.decodeIfPresent(Int.self, forKey: .wait) ?? 0
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
	
	nonisolated struct Usage: Sendable, Equatable {
		var memory: Int64
		var memoryTotal: Int64
		var storage: Int64
		var storageTotal: Int64
	}
	
	nonisolated enum Notice: Sendable, Equatable {
		case shows(ShowList)
		case refused(Refusal)
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
	
	static func gathered(_ log: Data) -> Data {
		let bytes = [UInt8](log)
		var latest: [String: (folder: String, body: ArraySlice<UInt8>)] = [:]
		var cursor = 0
		
		while cursor + recordHeader <= bytes.count {
			let folderStart = cursor + recordHeader
			let idStart = folderStart + Int(bytes[cursor + 1])
			let bodyStart = idStart + Int(bytes[cursor + 2])
			let end = bodyStart + (Int(bytes[cursor + 3]) | (Int(bytes[cursor + 4]) << 8))
			guard end <= bytes.count else { break }
			let folder = String(decoding: bytes[folderStart..<idStart], as: UTF8.self)
			let key = "\(folder)/\(String(decoding: bytes[idStart..<bodyStart], as: UTF8.self))"
			
			if bytes[cursor] == 0 {
				latest[key] = (folder, bytes[bodyStart..<end])
			} else {
				latest[key] = nil
			}
			
			cursor = end
		}
		
		var folders: [String: [ArraySlice<UInt8>]] = [:]
		
		for (folder, body) in latest.values {
			folders[folder, default: []].append(body)
		}
		
		var json = Data("{".utf8)
		
		for (folder, bodies) in folders {
			if json.count > 1 { json.append(UInt8(ascii: ",")) }
			json.append(Data("\"\(folder)\":[".utf8))
			
			for (index, body) in bodies.enumerated() {
				if index > 0 { json.append(UInt8(ascii: ",")) }
				json.append(contentsOf: body)
			}
			
			json.append(UInt8(ascii: "]"))
		}
		
		json.append(UInt8(ascii: "}"))
		return json
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
				var reason: String?
				var set: Bool?
				var refused: String?
				var wait: Int?
				var ram: Int64?
				var ramTotal: Int64?
				var store: Int64?
				var storeTotal: Int64?
				
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
			case "locked":
				guard let lock = try? JSONDecoder().decode(Lock.self, from: data) else { return nil }
				return .locked(lock)
			case "password":
				if let set = envelope.set { return .password(isSet: set) }
				return .passwordRefused(envelope.refused == "wrong" ? .wrong(wait: envelope.wait ?? 0) : .failed)
			case "pong":
				guard let ram = envelope.ram, let ramTotal = envelope.ramTotal, let store = envelope.store, let storeTotal = envelope.storeTotal else { return .pong(envelope.seq ?? 0, nil) }
				return .pong(envelope.seq ?? 0, Usage(memory: ram, memoryTotal: ramTotal, storage: store, storageTotal: storeTotal))
			case "master":
				guard let level = envelope.level else { return nil }
				return .master(level)
			case "blackout":
				guard let on = envelope.on else { return nil }
				return .blackout(on)
			case "scene":
				guard let identifier = envelope.id else { return nil }
				return .scene(identifier)
			case "refused":
				guard let refusal = envelope.reason.flatMap(Refusal.init(rawValue:)) else { return nil }
				return .notice(.refused(refusal))
			case "shows":
				guard let list = try? JSONDecoder().decode(ShowList.self, from: data) else { return nil }
				return .notice(.shows(list))
			case "wrote", "unwritten":
				guard let place = envelope.place else { return nil }
				return .notice(.landed(place, envelope.t == "wrote"))
			case "doc":
				guard let place = envelope.place else { return nil }
				return .notice(.stored(place, nil))
			default:
				return nil
			}
		@unknown default:
			return nil
		}
	}
}
