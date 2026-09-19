import SwiftUI

struct ChannelsView: View {
	let programmer: Programmer
	
	var body: some View {
		List {
			Section {
			} footer: {
				Text("A slider steps over a setting that has to be confirmed, so nothing resets a head by accident. Pick it below to send it, or type the value.")
			}
			
			ForEach(programmer.channels) { channel in
				Section {
					LabeledContent {
						TextField("Value", value: programmer.rawBinding(channel), format: .number.precision(.fractionLength(0)).grouping(.never))
							.keyboardType(.numberPad)
							.multilineTextAlignment(.trailing)
							.monospacedDigit()
							.frame(maxWidth: 80)
					} label: {
						HStack {
							Text(programmer.bandLabel(of: channel))
								.lineLimit(1)
							
							Spacer()
							
							Text(programmer.percent(of: channel), format: .percent.precision(.fractionLength(0)))
								.monospacedDigit()
								.foregroundStyle(.secondary)
						}
					}
					.font(.subheadline)
					
					Slider(value: programmer.guardedBinding(channel), in: 0...Double(channel.maximum), neutralValue: Double(channel.neutral)) {
						Text(channel.name)
					}
					.tint(channel.attribute.color)
					
					if channel.isBanded {
						BandPicker(programmer: programmer, channel: channel, bands: channel.functions)
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
