import Foundation

nonisolated struct Identity: Hashable, Sendable {
	let value = UUID()

	static func == (lhs: Self, rhs: Self) -> Bool { true }

	func hash(into hasher: inout Hasher) {}
}
