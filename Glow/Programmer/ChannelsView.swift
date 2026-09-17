import SwiftUI

struct ChannelsView: View {
	let programmer: Programmer
	
	var body: some View {
		List {
			Section {
			} footer: {
				Text("A slider stays inside the setting the channel is on, so nothing resets a head by accident. Pick another setting below it, or type the value.")
			}
			
			ForEach(programmer.parameters) { parameter in
				Section {
					LabeledContent {
						TextField("Value", value: programmer.rawBinding(parameter), format: .number.precision(.fractionLength(0)).grouping(.never))
							.keyboardType(.numberPad)
							.multilineTextAlignment(.trailing)
							.monospacedDigit()
							.frame(maxWidth: 80)
					} label: {
						HStack {
							Text(programmer.bandLabel(of: parameter))
								.lineLimit(1)
							
							Spacer()
							
							Text(programmer.percent(of: parameter), format: .percent.precision(.fractionLength(0)))
								.monospacedDigit()
								.foregroundStyle(.secondary)
						}
					}
					.font(.subheadline)
					
					Slider(value: programmer.rawBinding(parameter), in: 0...Double(parameter.maximum), neutralValue: parameter.neutral, enabledBounds: programmer.enabledBounds(of: parameter)) {
						Text(parameter.name)
					}
					.tint(parameter.role.color)
					
					if parameter.isBanded {
						BandPicker(programmer: programmer, channel: parameter.coarse, bands: parameter.ranges)
					}
				} header: {
					LabeledContent(parameter.name, value: programmer.channelLabel(of: parameter))
						.monospacedDigit()
				}
			}
		}
		.navigationTitle("All Channels")
		.navigationBarTitleDisplayMode(.inline)
	}
}
