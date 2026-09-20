import SwiftUI

struct ChannelRow: View {
	let programmer: Programmer
	let channel: FixtureChannel
	
	var body: some View {
		let blocker = programmer.blocker(of: channel)
		
		Group {
			if channel.functions.count > 1 {
				SlotPicker(programmer: programmer, channel: channel)
			} else {
				VStack(alignment: .leading, spacing: 6) {
					LabeledContent {
						Text(programmer.physical(of: channel) ?? "\(programmer.value(of: channel))")
							.monospacedDigit()
							.foregroundStyle(.secondary)
							.contentTransition(.numericText())
					} label: {
						Text(channel.name)
					}
					
					Slider(value: programmer.binding(channel), in: 0...255, neutralValue: Double(channel.defaultValue)) {
						Text(channel.name)
					}
					.tint(channel.attribute.color)
				}
			}
		}
		.disabled(blocker != nil)
		.opacity(blocker == nil ? 1 : 0.45)
		
		if let blocker {
			Label("\(blocker.name) has this channel switched off.", systemImage: "exclamationmark.circle")
				.font(.caption)
				.foregroundStyle(.secondary)
		}
	}
}
