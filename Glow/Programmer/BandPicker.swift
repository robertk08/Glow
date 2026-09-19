import SwiftUI

struct BandPicker: View {
	let programmer: Programmer
	let channel: FixtureChannel
	let bands: [ChannelFunction]
	
	@State private var pending: ChannelFunction?
	
	private let columns = [GridItem(.adaptive(minimum: 44), spacing: 12)]
	
	private var swatches: [ChannelFunction] { bands.filter { !$0.swatch.isEmpty } }
	
	private func choose(_ range: ChannelFunction) {
		guard !range.requiresConfirmation else {
			pending = range
			return
		}
		
		Task {
			await programmer.send(range, channel: channel)
		}
	}
	
	var body: some View {
		Group {
			Picker(channel.name, selection: Binding { programmer.band(of: channel)?.id ?? "" } set: { id in
				guard let range = bands.first(where: { $0.id == id }) else { return }
				choose(range)
			}) {
				if let active = programmer.band(of: channel), !bands.contains(active) {
					Text(active.label).tag(active.id)
				}
				
				if programmer.band(of: channel) == nil {
					Text("\(programmer.value(of: channel))").tag("")
				}
				
				ForEach(bands) { range in
					Text(range.label).tag(range.id)
				}
			}
			
			if !swatches.isEmpty {
				LazyVGrid(columns: columns, spacing: 12) {
					ForEach(swatches) { range in
						Button {
							choose(range)
						} label: {
							Swatch(colors: range.swatch, isSelected: programmer.band(of: channel) == range)
						}
						.buttonStyle(.plain)
						.accessibilityLabel(range.label)
						.accessibilityAddTraits(programmer.band(of: channel) == range ? .isSelected : [])
					}
				}
				.padding(.vertical, 4)
			}
		}
		.alert("Send \(pending?.label ?? "")?", item: $pending) { range in
			Button("Cancel", role: .cancel) {}
			
			Button("Send", role: .destructive) {
				Task {
					await programmer.send(range, channel: channel)
				}
			}
		} message: { _ in
			Text("This command can interrupt light output or movement. Glow holds timed commands for the fixture’s required duration.")
		}
	}
}
