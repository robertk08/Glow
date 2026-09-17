import SwiftUI

enum FeedbackType {
	case selection, success, error, warning, light, soft, medium, heavy, rigid
}

struct Haptic {
	@MainActor static func feedback(_ type: FeedbackType) {
		switch type {
		case .selection:
			UISelectionFeedbackGenerator().selectionChanged()
		case .success:
			UINotificationFeedbackGenerator().notificationOccurred(.success)
		case .error:
			UINotificationFeedbackGenerator().notificationOccurred(.error)
		case .warning:
			UINotificationFeedbackGenerator().notificationOccurred(.warning)
		case .light, .soft, .medium, .heavy, .rigid:
			let style: UIImpactFeedbackGenerator.FeedbackStyle = switch type {
			case .light: .light
			case .soft: .soft
			case .medium: .medium
			case .heavy: .heavy
			default: .rigid
			}
			UIImpactFeedbackGenerator(style: style).impactOccurred()
		}
	}
}
