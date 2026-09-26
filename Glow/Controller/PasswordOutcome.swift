import Foundation

nonisolated enum PasswordOutcome: Sendable, Equatable {
	case saving
	case saved
	case wrong(wait: Int)
	case failed
	
	var message: String? {
		switch self {
		case .saving, .saved: nil
		case .wrong(wait: 0): "The current password is wrong."
		case .wrong: "Too many wrong tries. Wait a moment and try again."
		case .failed: "The controller couldn't store the password, so nothing changed."
		}
	}
}
