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
				Task {
					await programmer.send(range, channel: channel)
				}
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
				Task {
					await programmer.send(range, channel: channel)
				}
			}
		} message: { _ in
			Text("This command can interrupt light output or movement. Glow holds timed commands for the fixture’s required duration.")
		}
	}
}
