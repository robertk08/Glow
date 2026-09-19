import SwiftData
import SwiftUI

nonisolated enum FixtureTint: String, CaseIterable, Identifiable, Sendable {
	case none, red, orange, yellow, green, mint, teal, blue, indigo, purple, pink
	
	var id: String { rawValue }
	
	var name: String { rawValue.capitalized }
	
	var color: Color? {
		switch self {
		case .none: nil
		case .red: .red
		case .orange: .orange
		case .yellow: .yellow
		case .green: .green
		case .mint: .mint
		case .teal: .teal
		case .blue: .blue
		case .indigo: .indigo
		case .purple: .purple
		case .pink: .pink
		}
	}
}
