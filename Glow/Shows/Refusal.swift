import Foundation

nonisolated enum Refusal: String, Sendable, Equatable {
	case storage
	case limit
	
	var title: String {
		switch self {
		case .storage: "The Controller Couldn't Store This"
		case .limit: "Too Many Shows"
		}
	}
	
	var message: String {
		switch self {
		case .storage: "Its storage is full or failing, so the change was undone. Controller in Settings shows how much room is left."
		case .limit: "The controller holds up to 64 shows. Delete one to make room for another."
		}
	}
}
