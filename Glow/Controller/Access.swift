import Foundation
import Observation

@Observable
final class Access {
	private(set) var lock: Wire.Lock?
	private(set) var lockedUntil: Date?
	private(set) var isUnlocking = false
	var passwordOutcome: PasswordOutcome?
	var post: (Wire.Command) -> Void = { _ in }
	
	private let connection: NodeLink
	private var offered: Data?
	private var proposed: Data?
	private var pause: Task<Void, Never>?
	
	init(connection: NodeLink) {
		self.connection = connection
	}
	
	func unlock(password: String) {
		guard let lock, !isUnlocking, lockedUntil == nil else { return }
		isUnlocking = true
		
		Task {
			offer(await Passkey.derive(password, id: lock.id))
		}
	}
	
	func protect(current: String, new: String, on node: Wire.NodeInfo) {
		passwordOutcome = .saving
		
		Task {
			var old: Data?
			var fresh: Data?
			
			if node.hasPassword {
				old = await Passkey.derive(current, id: node.id)
			}
			
			if !new.isEmpty {
				fresh = await Passkey.derive(new, id: node.id)
			}
			
			proposed = fresh
			post(.password(old: old, new: fresh, nonce: node.nonce))
		}
	}
	
	func admit() {
		if let offered, let lock {
			Passkey.store(offered, id: lock.id)
		}
		
		offered = nil
		lock = nil
		lockedUntil = nil
		isUnlocking = false
		pause?.cancel()
	}
	
	func challenge(_ challenge: Wire.Lock) {
		var challenge = challenge
		
		if challenge.isWrong, offered == Passkey.stored(id: challenge.id) {
			Passkey.forget(id: challenge.id)
			challenge.isWrong = false
		}
		
		lock = challenge
		offered = nil
		isUnlocking = false
		lockedUntil = nil
		pause?.cancel()
		
		guard challenge.wait == 0 else {
			lockedUntil = Date().addingTimeInterval(TimeInterval(challenge.wait))
			pause = Task { [weak self] in
				try? await Task.sleep(for: .seconds(challenge.wait))
				guard !Task.isCancelled, let self else { return }
				lockedUntil = nil
				guard let key = Passkey.stored(id: challenge.id) else { return }
				offer(key)
			}
			return
		}
		
		guard !challenge.isWrong, let key = Passkey.stored(id: challenge.id) else { return }
		offer(key)
	}
	
	func protected(id: String) {
		if let proposed {
			Passkey.store(proposed, id: id)
		} else {
			Passkey.forget(id: id)
		}
		
		proposed = nil
		if passwordOutcome == .saving { passwordOutcome = .saved }
	}
	
	func refused(_ outcome: PasswordOutcome) {
		proposed = nil
		passwordOutcome = outcome
	}
	
	private func offer(_ key: Data) {
		guard let lock else { return }
		isUnlocking = true
		offered = key
		let message = Wire.Command.unlock(key: key, nonce: lock.nonce).message
		
		Task {
			await connection.send(message)
		}
	}
}
