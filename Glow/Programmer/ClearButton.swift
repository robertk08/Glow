import SwiftData
import SwiftUI

struct ClearButton: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	var body: some View {
		Button("Clear", role: .cancel) {
			console.selection.clear()
		}
		.accessibilityHint("Tap to clear the selection. Touch and hold to reset those lights to their defaults.")
		.keyboardShortcut(.escape, modifiers: [])
		.simultaneousGesture(LongPressGesture().onEnded { _ in
			console.reset(among: fixtures, library: library)
		})
		.sensoryFeedback(.impact(weight: .light), trigger: console.selection.isEmpty)
		.sensoryFeedback(.impact(weight: .heavy), trigger: console.resets)
	}
}
