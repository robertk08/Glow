import SwiftUI

struct BandPicker: View {
	let programmer: Programmer
	let channel: ProfileChannel
	let bands: [ChannelRange]
	
	@State private var pending: ChannelRange?
	
	var body: some View {
		Picker(channel.name, selection: Binding { programmer.band(of: channel)?.id ?? "" } set: { id in
			guard let range = bands.first(where: { $0.id == id }) else { return }
			
			if range.requiresConfirmation {
				pending = range
			} else {
				programmer.set(range.midpoint, of: channel)
			}
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
		.alert("Send \(pending?.label ?? "")?", item: $pending) { range in
			Button("Cancel", role: .cancel) {}
			
			Button("Send", role: .destructive) {
				programmer.set(range.midpoint, of: channel)
			}
		} message: { _ in
			Text("The light stops answering the desk.")
		}
	}
}
