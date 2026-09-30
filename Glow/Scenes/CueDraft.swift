import Foundation

nonisolated struct CueDraft: Sendable, Equatable {
	var label = ""
	var fade = 0.0
	var delay = 0.0
	var follow: Double?
	var aspects = Set(FeatureGroup.allCases)
	var lights: Set<String>?
}
