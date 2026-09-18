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
	
	@State private var isRemoving = false
	@State private var origin: Double?
	
	var body: some View {
		let profile = library.profile(fixture.profileID)
		let programmer = Programmer(fixture: fixture, library: library, console: console)
		let isOn = programmer?.isOn ?? false
		let glow = programmer?.glow ?? .accentColor
		let isSelected = console.isSelected(fixture)
		
		return VStack(alignment: .leading, spacing: 10) {
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
		.containerShape(.rect(cornerRadius: 24, style: .continuous))
		.contentShape(.rect(cornerRadius: 24, style: .continuous))
		.onTapGesture {
			console.toggle(fixture)
		}
		.gesture(DragGesture(minimumDistance: 12).onChanged { drag in
			guard let programmer, programmer.dims else { return }
			guard origin != nil || abs(drag.translation.width) > abs(drag.translation.height) else { return }
			let start = origin ?? programmer.brightness
			origin = start
			programmer.brightness = start + drag.translation.width / 180
		}.onEnded { _ in
			origin = nil
		})
		.contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 24, style: .continuous))
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
