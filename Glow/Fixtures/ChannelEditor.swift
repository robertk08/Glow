import SwiftUI

struct ChannelEditor: View {
	@Binding var channel: FixtureChannel
	
	let others: [FixtureChannel]
	
	var body: some View {
		Form {
			Section {
				Picker("Does", selection: $channel.attribute) {
					ForEach(FeatureGroup.allCases) { group in
						Section(group.name) {
							ForEach(Attribute.allCases.filter { $0.group == group }) { attribute in
								Label(attribute.name, systemImage: attribute.symbol).tag(attribute)
							}
						}
					}
				}
				
				TextField(channel.attribute.name, text: Binding { channel.label ?? "" } set: { channel.label = $0.isEmpty ? nil : $0 })
			} header: {
				Text("Channel \(channel.addressLabel)")
			} footer: {
				Text("The attribute is what Glow drives, so the same control reaches it on every fixture that has one. The name is only what you read.")
			}
			
			Section {
				Toggle("16-bit", isOn: Binding { channel.isWide } set: { channel.fineOffset = $0 ? channel.offset + 1 : nil })
			} footer: {
				Text("On when the next address is the fine half of this one, giving the attribute 65,536 steps instead of 256.")
			}
			
			Section {
				LabeledContent("Starts at", value: "\(channel.defaultValue)")
					.monospacedDigit()
				
				Slider(value: Binding { Double(channel.defaultValue) } set: { channel.defaultValue = UInt8($0.rounded()) }, in: 0...255) {
					Text("Starts at")
				}
				
				if channel.isWide {
					LabeledContent("Fine half starts at", value: "\(channel.fineDefaultValue)")
						.monospacedDigit()
					
					Slider(value: Binding { Double(channel.fineDefaultValue) } set: { channel.fineDefaultValue = UInt8($0.rounded()) }, in: 0...255) {
						Text("Fine half starts at")
					}
				}
			} header: {
				Text("Default")
			} footer: {
				Text("Where the channel sits before anyone touches it. It goes out on the wire but counts as unset, so raising the dimmer does not turn a default into something you chose.")
			}
			
			Section {
				LabeledContent("Highlight", value: channel.highlightValue.map { "\($0)" } ?? "Automatic")
					.monospacedDigit()
				
				Slider(value: Binding { Double(channel.highlightValue ?? channel.highlight ?? 0) } set: { channel.highlightValue = UInt8($0.rounded()) }, in: 0...255) {
					Text("Highlight")
				}
				
				if channel.highlightValue != nil {
					Button("Back to Automatic") {
						channel.highlightValue = nil
					}
				}
			} header: {
				Text("Highlight")
			} footer: {
				Text("Where Highlight puts this channel when you are finding a light on stage. Automatic opens the shutter and takes the dimmer to full.")
			}
			
			Section {
				ForEach($channel.functions) { $function in
					NavigationLink {
						FunctionEditor(function: $function)
					} label: {
						LabeledContent {
							Text(function.label)
								.multilineTextAlignment(.trailing)
						} label: {
							VStack(alignment: .leading, spacing: 2) {
								Text("\(function.from)–\(function.to)")
									.monospacedDigit()
									.foregroundStyle(.secondary)
								
								if let purpose = function.purpose {
									Text(purpose.rawValue.capitalized)
										.font(.caption2)
										.foregroundStyle(.tint)
								} else if !function.sets.isEmpty {
									Text("^[\(function.sets.count) slot](inflect: true)")
										.font(.caption2)
										.foregroundStyle(.secondary)
								}
							}
						}
					}
				}
				.onDelete { channel.functions.remove(atOffsets: $0) }
				
				Button("Add Range", systemImage: "plus") {
					let start = channel.functions.map { Int($0.to) + 1 }.max() ?? 0
					channel.functions.append(ChannelFunction(from: UInt8(min(start, 255)), to: 255, label: "Range \(channel.functions.count + 1)"))
					channel.functions.sort { $0.from < $1.from }
				}
			} header: {
				Text("Ranges")
			} footer: {
				Text("A channel with ranges gets a named picker. One without gets a plain slider on the raw value.")
			}
			
			Section {
				Picker("Only works when", selection: Binding { channel.enabledBy?.offset ?? 0 } set: { offset in
					guard offset > 0 else {
						channel.enabledBy = nil
						return
					}
					channel.enabledBy = FixtureChannel.Dependency(offset: offset, from: 0, to: 255)
				}) {
					Text("Always").tag(0)
					
					ForEach(others.filter { $0.offset != channel.offset }) { other in
						Text(other.name).tag(other.offset)
					}
				}
				
				if let dependency = channel.enabledBy {
					LabeledContent("is between", value: "\(dependency.from) and \(dependency.to)")
						.monospacedDigit()
					
					Slider(value: Binding { Double(dependency.from) } set: { channel.enabledBy?.from = UInt8(min($0.rounded(), Double(dependency.to))) }, in: 0...255) {
						Text("From")
					}
					
					Slider(value: Binding { Double(dependency.to) } set: { channel.enabledBy?.to = UInt8(max($0.rounded(), Double(dependency.from))) }, in: 0...255) {
						Text("To")
					}
				}
			} header: {
				Text("Depends on")
			} footer: {
				Text("For a fixture whose colour channels go dead while a built-in pattern runs. Glow greys this channel out and says which one switched it off.")
			}
		}
		.navigationTitle(channel.name)
		.navigationBarTitleDisplayMode(.inline)
	}
}
