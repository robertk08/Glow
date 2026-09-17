import SwiftData
import SwiftUI

struct LightTile: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.modelContext) private var context
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	let fixture: Fixture
	let clashes: Bool
	
	@Binding var editing: Fixture?
	
	var body: some View {
		let profile = library.profile(fixture.profileID)
		let programmer = Programmer(fixture: fixture, library: library, console: console)
		let isOn = programmer?.isOn ?? false
		let glow = programmer?.glow ?? .accentColor
		let isSelected = console.isSelected(fixture)
		
		return Button {
			console.toggle(fixture)
		} label: {
			VStack(alignment: .leading, spacing: 10) {
				HStack {
					Image(systemName: clashes ? "exclamationmark.triangle.fill" : fixture.symbol(profile))
						.font(.title3)
						.foregroundStyle(isOn || clashes ? programmer?.displayInk ?? .white : .secondary)
						.frame(width: 38, height: 38)
						.background(clashes ? Color.orange : isOn ? glow : Color(.tertiarySystemFill), in: .circle)
						.overlay {
							Circle()
								.strokeBorder(.separator)
						}
					
					Spacer()
					
					Image(systemName: "checkmark.circle.fill")
						.font(.title3)
						.foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
				}
				
				Text(fixture.name)
					.font(.headline)
					.lineLimit(1)
				
				if let programmer, programmer.dims {
					Gauge(value: programmer.brightness) {
						Text(fixture.name)
					}
					.gaugeStyle(.accessoryLinearCapacity)
					.tint(isOn ? glow : Color(.tertiarySystemFill))
					.labelsHidden()
				}
			}
			.foregroundStyle(.primary)
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(14)
			.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24, style: .continuous))
			.overlay {
				RoundedRectangle(cornerRadius: 24, style: .continuous)
					.strokeBorder(.tint, lineWidth: isSelected ? 3 : 0)
			}
		}
		.buttonStyle(.plain)
		.containerShape(.rect(cornerRadius: 24, style: .continuous))
		.accessibilityElement(children: .combine)
		.accessibilityLabel(fixture.name)
		.accessibilityValue(clashes ? "address clash" : programmer?.spokenState ?? "unpatched")
		.accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
		.contextMenu {
			Button(isOn ? "Turn Off" : "Turn On", systemImage: isOn ? "lightbulb.slash" : "lightbulb.max") {
				programmer?.toggleOn()
			}
			
			Button("Edit Light", systemImage: "slider.horizontal.3") {
				editing = fixture
			}
			
			Button("Duplicate", systemImage: "plus.square.on.square") {
				console.duplicate(fixture, among: fixtures, library: library, context: context)
			}
			
			Button("Remove Light", systemImage: "trash", role: .destructive) {
				console.remove(fixture, context: context, library: library)
			}
		}
	}
}
