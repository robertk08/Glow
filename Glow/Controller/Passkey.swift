import CommonCrypto
import CryptoKit
import Foundation
import Security

nonisolated enum Passkey {
	private static let length = 32
	private static let rounds: UInt32 = 100_000
	private static let service = "Glow Controller"
	
	@concurrent static func derive(_ password: String, id: String) async -> Data {
		let salt = Array("glow:\(id)".utf8)
		var key = [UInt8](repeating: 0, count: length)
		CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password, password.utf8.count, salt, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds, &key, length)
		return Data(key)
	}
	
	static func proof(_ label: String, nonce: String, key: Data?) -> String {
		guard let key else { return "" }
		return hex(mac(label, nonce: nonce, key: key))
	}
	
	static func wrap(_ fresh: Data?, nonce: String, key: Data?) -> String {
		guard let fresh else { return "" }
		guard let key else { return hex(fresh) }
		return hex(Data(zip(fresh, mac("wrap", nonce: nonce, key: key)).map { $0 ^ $1 }))
	}
	
	static func stored(id: String) -> Data? {
		var item: CFTypeRef?
		let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id, kSecReturnData as String: true]
		guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
		return item as? Data
	}
	
	static func store(_ key: Data, id: String) {
		forget(id: id)
		let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, kSecValueData as String: key]
		SecItemAdd(item as CFDictionary, nil)
	}
	
	static func forget(id: String) {
		let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id]
		SecItemDelete(query as CFDictionary)
	}
	
	private static func mac(_ label: String, nonce: String, key: Data) -> Data {
		Data(HMAC<SHA256>.authenticationCode(for: Data((label + nonce).utf8), using: SymmetricKey(data: key)))
	}
	
	private static func hex(_ data: Data) -> String {
		data.map { String(format: "%02x", $0) }.joined()
	}
}
