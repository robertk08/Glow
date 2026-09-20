import SwiftUI

struct SlotPicker: View {
	let programmer: Programmer
	let channel: FixtureChannel
	
	@State private var pending: ChannelFunction?
	
	private let columns = [GridItem(.adaptive(minimum: 44), spacing: 12)]
	
	var body: some View {
		let active = programmer.band(of: channel)
		let swatches = programmer.swatches(of: channel)
		let selected = programmer.selection(of: channel)
		
		Group {
			Picker(channel.name, selection: Binding { selected } set: { id in
				guard let chosen = programmer.choice(id, of: channel) else { return }
				
				guard !chosen.confirms else {
					pending = chosen.function
					return
				}
				
				Task {
					await programmer.send(chosen, of: channel)
				}
			}) {
				if active == nil {
					Text("\(programmer.value(of: channel))").tag("")
				}
				
				ForEach(programmer.choices(of: channel)) { choice in
					Text(choice.label).tag(choice.id)
				}
			}
			
			if !swatches.isEmpty {
				LazyVGrid(columns: columns, spacing: 12) {
					ForEach(swatches) { choice in
						Button {
							Task {
								await programmer.send(choice, of: channel)
							}
						} label: {
							if let shape = choice.shape {
								GoboMark(shape: shape, tint: programmer.glow, angle: programmer.goboAngle ?? .zero, turns: choice.id == selected ? programmer.goboTurns : nil, isSelected: choice.id == selected)
							} else {
								Swatch(colors: choice.swatch, isSelected: choice.id == selected)
							}
						}
						.buttonStyle(.plain)
						.accessibilityLabel(choice.label)
						.accessibilityAddTraits(choice.id == selected ? .isSelected : [])
					}
				}
				.padding(.vertical, 4)
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
