import SwiftData
import SwiftUI

struct ConsoleBar: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	let transition: Namespace.ID
	
	var body: some View {
		let programmer = console.programmer(among: fixtures, library: library)
		
		return Group {
			if !console.selection.isEmpty {
				HStack(spacing: 8) {
					Button {
						console.selection.isProgrammerOpen = true
					} label: {
						HStack(spacing: 8) {
							Image(systemName: programmer.symbol)
								.font(.caption)
								.foregroundStyle(programmer.isOn ? programmer.displayInk : Color.secondary)
								.frame(width: 26, height: 26)
								.background(programmer.isOn ? programmer.glow : Color(.tertiarySystemFill), in: .circle)
							
							Text(programmer.title)
								.font(.subheadline.weight(.medium))
								.lineLimit(1)
						}
						.contentShape(.rect)
					}
					.buttonStyle(.plain)
					.layoutPriority(1)
					.matchedTransitionSource(id: "programmer", in: transition)
					
					if programmer.dims {
						Slider(value: programmer.brightnessBinding, in: 0...1) {
							Text("Intensity")
						}
						.frame(minWidth: 48)
						.tint(programmer.isOn ? programmer.glow : nil)
						.simultaneousGesture(TapGesture().onEnded {
							console.selection.isProgrammerOpen = true
						})
					} else {
						Spacer(minLength: 8)
					}
					
					ClearButton()
						.fixedSize()
				}
				.padding(.horizontal, 12)
			} else {
				MasterBar()
			}
		}
		.sensoryFeedback(.selection, trigger: console.selection.identifiers)
	}
}
