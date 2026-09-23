import SwiftUI

struct SlotPicker: View {
	let programmer: Programmer
	let channel: FixtureChannel
	
	@State private var pending: Programmer.Choice?
	@State private var picks = 0
	
	private let columns = [GridItem(.adaptive(minimum: 72), spacing: 10)]
	private let stopColumns = [GridItem(.adaptive(minimum: 76), spacing: 8)]
	
	private func choose(_ choice: Programmer.Choice) {
		guard !choice.confirms else {
			pending = choice
			return
		}
		
		picks += 1
		
		Task {
			await programmer.send(choice, of: channel)
		}
	}
	
	@ViewBuilder private var scaleRows: some View {
		if let scale = programmer.scale(of: channel) {
			VStack(alignment: .leading, spacing: 6) {
				LabeledContent {
					Text(programmer.physical(of: channel) ?? programmer.bandLabel(of: channel))
						.monospacedDigit()
						.foregroundStyle(.secondary)
						.contentTransition(.numericText())
				} label: {
					Text(channel.name)
				}
				
				Slider(value: programmer.binding(channel), in: Double(scale.from)...Double(scale.to)) {
					Text(channel.name)
				}
			}
			
			let stops = programmer.stops(of: channel)
			
			if !stops.isEmpty {
				let mode = programmer.mode(of: channel)
				
				LazyVGrid(columns: stopColumns, spacing: 8) {
					ForEach(stops) { stop in
						Button(stop.label) {
							choose(stop)
						}
						.frame(maxWidth: .infinity)
						.tint(stop.id == mode ? Color.accentColor : nil)
					}
				}
				.buttonStyle(.glass)
				.controlSize(.small)
				.padding(.vertical, 2)
			}
		}
	}
	
	@ViewBuilder private var bandRows: some View {
		let slots = programmer.slots(of: channel)
		let selected = programmer.selection(of: channel)
		
		Picker(channel.name, selection: Binding { programmer.mode(of: channel) } set: { id in
			guard let chosen = programmer.choice(id, of: channel) else { return }
			choose(chosen)
		}) {
			if programmer.band(of: channel) == nil {
				Text("\(programmer.value(of: channel))").tag("")
			}
			
			ForEach(programmer.modes(of: channel)) { mode in
				Text(mode.label).tag(mode.id)
			}
		}
		
		if !slots.isEmpty, programmer.isMarked(channel) {
			LazyVGrid(columns: columns, spacing: 12) {
				ForEach(slots) { slot in
					Button {
						choose(slot)
					} label: {
						VStack(spacing: 4) {
							if let shape = slot.shape {
								GoboMark(shape: shape, size: 50, tint: programmer.glow, isSelected: slot.id == selected)
							} else {
								Swatch(colors: slot.swatch, size: 50, isSelected: slot.id == selected)
							}
							
							Text(slot.label)
								.font(.caption2)
								.multilineTextAlignment(.center)
								.lineLimit(2, reservesSpace: true)
								.minimumScaleFactor(0.8)
								.foregroundStyle(slot.id == selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
						}
					}
					.buttonStyle(.plain)
				}
			}
			.padding(.vertical, 4)
		} else if !slots.isEmpty {
			Picker("Slot", selection: Binding { selected } set: { id in
				guard let chosen = programmer.choice(id, of: channel) else { return }
				choose(chosen)
			}) {
				ForEach(slots) { slot in
					Text(slot.label).tag(slot.id)
				}
			}
		}
		
		if let adjustable = programmer.adjustableBand(of: channel), adjustable.sets.isEmpty {
			Slider(value: programmer.binding(channel), in: Double(adjustable.from)...Double(adjustable.to)) {
				Text(adjustable.label)
			}
		}
	}
	
	var body: some View {
		Group {
			if programmer.scale(of: channel) != nil {
				scaleRows
			} else {
				bandRows
			}
		}
		.sensoryFeedback(.selection, trigger: picks)
		.alert("Send \(pending?.label ?? "")?", isPresented: Binding { pending != nil } set: { _ in pending = nil }, presenting: pending) { choice in
			Button("Cancel", role: .cancel) {}
			
			Button("Send", role: .destructive) {
				Task {
					await programmer.send(choice, of: channel)
				}
			}
		} message: { _ in
			Text("This can interrupt the light or move the head. Glow holds it for the time the fixture needs, then puts the channel back.")
		}
	}
}
