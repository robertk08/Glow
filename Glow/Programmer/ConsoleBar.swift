import SwiftData
import SwiftUI

struct ConsoleBar: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.tabViewBottomAccessoryPlacement) private var placement
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	let transition: Namespace.ID
	
	var body: some View {
		let programmer = console.programmer(among: fixtures, library: library)
		
		return Group {
			if console.hasSelection {
				HStack(spacing: 10) {
					Button {
						console.isProgrammerOpen = true
					} label: {
						HStack(spacing: 8) {
							Image(systemName: programmer.symbol)
								.font(.caption)
								.foregroundStyle(programmer.isOn ? programmer.displayInk : Color.secondary)
								.frame(width: 26, height: 26)
								.background(programmer.isOn ? programmer.glow : Color(.tertiarySystemFill), in: .circle)
							
							VStack(alignment: .leading, spacing: 0) {
								Text(programmer.title)
									.font(.subheadline.weight(.medium))
									.lineLimit(1)
								
								if !programmer.activeGroups.isEmpty {
									HStack(spacing: 3) {
										ForEach(programmer.activeGroups) { group in
											Image(systemName: group.symbol)
												.font(.system(size: 8))
										}
									}
									.foregroundStyle(.tint)
								}
							}
							
							if !console.link.isConnected {
								Image(systemName: "wifi.exclamationmark")
									.foregroundStyle(.orange)
							}
						}
						.contentShape(.rect)
					}
					.buttonStyle(.plain)
					.layoutPriority(1)
					.matchedTransitionSource(id: "programmer", in: transition)
					
					if programmer.dims, placement == .expanded {
						Slider(value: programmer.brightnessBinding, in: 0...1) {
							Text("Brightness")
						}
						.frame(minWidth: 70)
						.tint(programmer.isOn ? programmer.glow : nil)
						.simultaneousGesture(TapGesture().onEnded {
							console.isProgrammerOpen = true
						})
					} else if programmer.dims {
						Spacer(minLength: 8)
						
						Text(programmer.brightness, format: .percent.precision(.fractionLength(0)))
							.font(.subheadline.monospacedDigit())
							.foregroundStyle(.secondary)
					} else {
						Spacer(minLength: 8)
					}
					
					ClearButton()
				}
				.padding(.horizontal, 12)
			} else {
				MasterBar()
			}
		}
		.sensoryFeedback(.selection, trigger: console.selection)
	}
}
