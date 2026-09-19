import Foundation

enum NodeSetupFailure: LocalizedError, Sendable {
	case unreachable
	case refused(String)
	
	var errorDescription: String? {
		switch self {
		case .unreachable: "Couldn't reach the node."
		case let .refused(reason): reason
		}
	}
}
