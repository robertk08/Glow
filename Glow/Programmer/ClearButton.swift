import SwiftData
import SwiftUI

struct ClearButton: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	var body: some View {
		Button("Clear", role: .cancel) {
			console.clearSelection()
		}
		.keyboardShortcut(.escape, modifiers: [])
		.disabled(!console.hasSelection)
		.contextMenu {
			Button("Release Values", systemImage: "arrow.uturn.backward", role: .destructive) {
				console.releaseValues(among: fixtures, library: library)
			}
		}
		.sensoryFeedback(.impact(weight: .light), trigger: console.hasSelection)
	}
}
