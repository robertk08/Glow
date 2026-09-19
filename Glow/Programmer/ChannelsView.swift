import SwiftUI

struct ChannelsView: View {
	let programmer: Programmer
	
	var body: some View {
		List {
			ForEach(programmer.channels) { channel in
				Section {
					LabeledContent {
						TextField("Value", value: programmer.rawBinding(channel), format: .number.precision(.fractionLength(0)).grouping(.never))
							.keyboardType(.numberPad)
							.multilineTextAlignment(.trailing)
							.monospacedDigit()
							.frame(maxWidth: 88)
					} label: {
						VStack(alignment: .leading, spacing: 2) {
							Text(programmer.bandLabel(of: channel))
								.lineLimit(1)
							
							if let physical = programmer.physical(of: channel) {
								Text(physical)
									.font(.caption)
									.foregroundStyle(.secondary)
									.monospacedDigit()
							}
						}
					}
					.font(.subheadline)
					
					Slider(value: programmer.guardedBinding(channel), in: 0...Double(channel.maximum), neutralValue: Double(channel.neutral)) {
						Text(channel.name)
					}
					.tint(channel.attribute.color)
					
					if channel.isBanded {
						SlotPicker(programmer: programmer, channel: channel)
					}
				} header: {
					LabeledContent(channel.name, value: programmer.channelLabel(of: channel))
						.monospacedDigit()
				}
			}
		}
		.navigationTitle("All Channels")
		.navigationBarTitleDisplayMode(.inline)
	}
}
