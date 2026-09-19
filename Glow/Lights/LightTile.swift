import SwiftData
import SwiftUI

struct LightTile: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.modelContext) private var context
	
	let fixture: Fixture
	let fixtures: [Fixture]
	let clashes: Bool
	
	@Binding var editing: Fixture?
	
	@State private var isRemoving = false
	@State private var start: CGPoint?
	@State private var origin = 0.0
	
	var body: some View {
		let mode = library.mode(fixture.typeID)
		let programmer = Programmer(fixture: fixture, library: library, console: console)
		let isOn = programmer?.isOn ?? false
		let glow = programmer?.glow ?? .accentColor
		let isSelected = console.selection.contains(fixture)
		
		return VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 8) {
				Image(systemName: clashes || programmer == nil ? "exclamationmark.triangle.fill" : fixture.symbol(mode))
					.font(.title3)
					.foregroundStyle(isOn || clashes || programmer == nil ? programmer?.displayInk ?? .white : .secondary)
					.frame(width: 38, height: 38)
					.background(clashes || programmer == nil ? Color.orange : isOn ? glow : Color(.tertiarySystemFill), in: .circle)
					.symbolEffect(.breathe, isActive: isOn && programmer?.strobeHertz != nil)
				
				Spacer()
				
				HStack(spacing: 3) {
					ForEach(programmer?.activeGroups ?? []) { group in
						Image(systemName: group.symbol)
							.font(.system(size: 9))
							.foregroundStyle(.tint)
					}
				}
				
				Image(systemName: "checkmark.circle.fill")
					.font(.title3)
					.foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
			}
			
			VStack(alignment: .leading, spacing: 1) {
				Text(fixture.name)
					.font(.headline)
					.lineLimit(1)
				
				Text(clashes ? "Shares channels" : programmer?.address ?? "Needs a fixture")
					.font(.caption2)
					.foregroundStyle(clashes || programmer == nil ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
					.monospacedDigit()
					.lineLimit(1)
			}
			
			if let programmer, programmer.dims {
				Gauge(value: programmer.brightness) {
					Text(fixture.name)
				}
				.gaugeStyle(.accessoryLinearCapacity)
				.tint(isOn ? glow : Color(.tertiarySystemFill))
				.labelsHidden()
				.padding(.vertical, 6)
				.contentShape(.rect)
				.gesture(DragGesture(minimumDistance: 4).onChanged { drag in
					if start != drag.startLocation {
						start = drag.startLocation
						origin = programmer.brightness - drag.translation.width / 180
					}
					
					programmer.brightness = origin + drag.translation.width / 180
				})
			}
		}
		.foregroundStyle(.primary)
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(14)
		.glassEffect(.regular.tint(isSelected ? .accentColor : nil).interactive(), in: .rect(cornerRadius: 24, style: .continuous))
		.contentShape(.rect(cornerRadius: 24, style: .continuous))
		.onTapGesture {
			guard programmer != nil else {
				editing = fixture
				return
			}
			
			console.selection.toggle(fixture)
		}
		.contentShape(.dragPreview, RoundedRectangle(cornerRadius: 24, style: .continuous))
		.accessibilityElement(children: .combine)
		.accessibilityAddTraits(.isButton)
		.accessibilityAddTraits(isSelected ? .isSelected : [])
		.contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 24, style: .continuous))
		.contextMenu {
			Button(isOn ? "Turn Off" : "Turn On", systemImage: isOn ? "lightbulb.slash" : "lightbulb.max") {
				programmer?.toggleOn()
			}
			
			Button("Highlight", systemImage: "flashlight.on.fill") {
				programmer?.highlight()
			}
			
			Button("Release Values", systemImage: "arrow.uturn.backward") {
				programmer?.applyDefaults()
			}
			
			Divider()
			
			Button("Edit Light", systemImage: "slider.horizontal.3") {
				editing = fixture
			}
			
			Button("Duplicate", systemImage: "plus.square.on.square") {
				console.duplicate(fixture, among: fixtures, library: library, context: context)
			}
			
			Button("Remove Light", systemImage: "trash", role: .destructive) {
				isRemoving = true
			}
		}
		.confirmationDialog("Remove \(fixture.name)?", isPresented: $isRemoving, titleVisibility: .visible) {
			Button("Remove Light", role: .destructive) {
				console.remove(fixture, context: context, library: library)
			}
		} message: {
			Text("Its channels go back to zero and any scene holding it forgets it.")
		}
	}
}
