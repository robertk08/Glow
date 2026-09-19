import SwiftUI

struct SlotPicker: View {
	let programmer: Programmer
	let channel: FixtureChannel
	
	@State private var pending: ChannelFunction?
	
	private let columns = [GridItem(.adaptive(minimum: 84), spacing: 10)]
	
	var body: some View {
		let active = programmer.band(of: channel)
		let slot = programmer.slot(of: channel)
		
		return Group {
			LazyVGrid(columns: columns, spacing: 10) {
				ForEach(programmer.bands(of: channel)) { function in
					if function.sets.isEmpty {
						SlotChip(label: function.label, swatch: function.swatch, isSelected: active == function && slot == nil) {
							guard !function.requiresConfirmation else {
								pending = function
								return
							}
							
							Task {
								await programmer.send(function, channel: channel)
							}
						}
					} else {
						ForEach(function.sets) { set in
							SlotChip(label: set.label, swatch: set.swatch, isSelected: slot == set) {
								programmer.send(set, channel: channel)
							}
						}
					}
				}
			}
			
			if let adjustable = programmer.adjustableBand(of: channel), adjustable.sets.isEmpty {
				LabeledContent(adjustable.label) {
					Text(programmer.physical(of: channel) ?? "\(programmer.value(of: channel))")
						.monospacedDigit()
						.foregroundStyle(.secondary)
				}
				.font(.subheadline)
				
				Slider(value: programmer.binding(channel), in: Double(adjustable.from)...Double(adjustable.to)) {
					Text(adjustable.label)
				}
			}
		}
		.alert("Send \(pending?.label ?? "")?", isPresented: Binding { pending != nil } set: { _ in pending = nil }, presenting: pending) { function in
			Button("Cancel", role: .cancel) {}
			
			Button("Send", role: .destructive) {
				Task {
					await programmer.send(function, channel: channel)
				}
			}
		} message: { _ in
			Text("This can interrupt the light or move the head. Glow holds it for the time the fixture needs, then puts the channel back.")
		}
	}
}

private struct SlotChip: View {
	let label: String
	let swatch: [LightColor]
	let isSelected: Bool
	let choose: () -> Void
	
	var body: some View {
		Button(action: choose) {
			VStack(spacing: 6) {
				if swatch.isEmpty {
					Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
						.font(.title3)
						.foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
						.frame(height: 26)
				} else {
					Swatch(colors: swatch, size: 26, isSelected: isSelected)
				}
				
				Text(label)
					.font(.caption2)
					.multilineTextAlignment(.center)
					.lineLimit(2)
					.foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
			}
			.frame(maxWidth: .infinity)
			.padding(.vertical, 8)
			.contentShape(.rect)
		}
		.buttonStyle(.plain)
		.accessibilityLabel(label)
		.accessibilityAddTraits(isSelected ? .isSelected : [])
	}
}
