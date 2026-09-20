import SwiftUI

struct SlotPicker: View {
	let programmer: Programmer
	let channel: FixtureChannel

	@State private var pending: ChannelFunction?

	private let columns = [GridItem(.adaptive(minimum: 48), spacing: 12)]

	private func choose(_ choice: Programmer.Choice) {
		guard !choice.confirms else {
			pending = choice.function
			return
		}

		Task {
			await programmer.send(choice, of: channel)
		}
	}

	var body: some View {
		let slots = programmer.slots(of: channel)
		let selected = programmer.selection(of: channel)

		Group {
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
							if let shape = slot.shape {
								GoboMark(shape: shape, size: 48, tint: programmer.glow, isSelected: slot.id == selected)
							} else {
								Swatch(colors: slot.swatch, isSelected: slot.id == selected)
							}
						}
						.buttonStyle(.plain)
						.accessibilityLabel(slot.label)
						.accessibilityAddTraits(slot.id == selected ? .isSelected : [])
					}
				}
				.padding(.vertical, 4)
				.sensoryFeedback(.selection, trigger: selected)
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
