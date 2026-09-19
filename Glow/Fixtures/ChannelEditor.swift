import SwiftUI

struct ChannelEditor: View {
	@Binding var channel: FixtureChannel
	
	@State private var isAddingFunction = false
	
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
				ForEach(channel.functions) { function in
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
							}
						}
					}
				}
				.onDelete { channel.functions.remove(atOffsets: $0) }
				
				Button("Add Range", systemImage: "plus") {
					isAddingFunction = true
				}
			} header: {
				Text("Ranges")
			} footer: {
				Text("A channel with ranges gets a named picker. One without gets a plain slider on the raw value. Marking a range as the dimmer is what tells Glow this channel carries intensity, so a fixture that dims through its shutter still answers the brightness fader.")
			}
		}
		.navigationTitle(channel.name)
		.navigationBarTitleDisplayMode(.inline)
		.sheet(isPresented: $isAddingFunction) {
			FunctionSheet(taken: channel.functions) { function in
				channel.functions.append(function)
				channel.functions.sort { $0.from < $1.from }
			}
		}
	}
}

private struct FunctionSheet: View {
	@Environment(\.dismiss) private var dismiss
	
	let taken: [ChannelFunction]
	let save: (ChannelFunction) -> Void
	
	@State private var from = 0.0
	@State private var to = 255.0
	@State private var label = ""
	@State private var kind = ChannelFunction.Kind.setting
	@State private var purpose: ChannelFunction.Purpose?
	@State private var unit: PhysicalUnit?
	@State private var physicalFrom = 0.0
	@State private var physicalTo = 0.0
	@State private var requiresConfirmation = false
	@State private var holdSeconds = 0.0
	
	var body: some View {
		NavigationStack {
			Form {
				Section {
					TextField("What it does", text: $label)
						.autocorrectionDisabled()
				}
				
				Section {
					LabeledContent("From", value: "\(Int(from))")
						.monospacedDigit()
					
					Slider(value: Binding { from } set: { from = $0.rounded() }, in: 0...255) {
						Text("From")
					}
					
					LabeledContent("To", value: "\(Int(to))")
						.monospacedDigit()
					
					Slider(value: Binding { to } set: { to = $0.rounded() }, in: 0...255) {
						Text("To")
					}
				} footer: {
					if to < from {
						Text("The end has to come after the start.")
							.foregroundStyle(.orange)
					}
				}
				
				Section {
					Picker("Control", selection: $kind) {
						Text("Setting").tag(ChannelFunction.Kind.setting)
						Text("Variable").tag(ChannelFunction.Kind.proportional)
					}
					
					Picker("Stands for", selection: $purpose) {
						Text("Nothing in particular").tag(ChannelFunction.Purpose?.none)
						Text("The dimmer").tag(ChannelFunction.Purpose?.some(.dim))
						Text("Fully open").tag(ChannelFunction.Purpose?.some(.open))
						Text("Blacked out").tag(ChannelFunction.Purpose?.some(.closed))
						Text("Hands color back to the mixer").tag(ChannelFunction.Purpose?.some(.release))
					}
					
					Toggle("Confirm Before Sending", isOn: $requiresConfirmation)
					
					Stepper(value: $holdSeconds, in: 0...60, step: 0.5) {
						LabeledContent("Hold", value: holdSeconds == 0 ? "Until Changed" : "\(holdSeconds.formatted()) s")
					}
				} header: {
					Text("Behavior")
				} footer: {
					Text("Variable ranges expose a slider. A timed command returns to the channel default after its hold time.")
				}
				
				Section {
					Picker("Reads in", selection: $unit) {
						Text("Raw value").tag(PhysicalUnit?.none)
						Text("Percent").tag(PhysicalUnit?.some(.percent))
						Text("Degrees").tag(PhysicalUnit?.some(.degrees))
						Text("Hertz").tag(PhysicalUnit?.some(.hertz))
						Text("Seconds").tag(PhysicalUnit?.some(.seconds))
						Text("Kelvin").tag(PhysicalUnit?.some(.kelvin))
						Text("RPM").tag(PhysicalUnit?.some(.rpm))
					}
					
					if unit != nil {
						TextField("At the start", value: $physicalFrom, format: .number)
							.keyboardType(.numbersAndPunctuation)
						
						TextField("At the end", value: $physicalTo, format: .number)
							.keyboardType(.numbersAndPunctuation)
					}
				} header: {
					Text("Real units")
				} footer: {
					Text("What the manual says this range means in the world, so Glow can show 3.2 Hz or 37° instead of a DMX number.")
				}
			}
			.navigationTitle("Add Range")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button(role: .cancel) { dismiss() }
				}
				
				ToolbarItem(placement: .confirmationAction) {
					Button(role: .confirm) {
						var function = ChannelFunction(from: UInt8(from), to: UInt8(to), label: label.trimmingCharacters(in: .whitespaces), kind: kind, purpose: purpose)
						function.requiresConfirmation = requiresConfirmation
						function.unit = unit
						if unit != nil { function.physicalFrom = physicalFrom }
						if unit != nil { function.physicalTo = physicalTo }
						if holdSeconds > 0 { function.holdSeconds = holdSeconds }
						save(function)
						dismiss()
					}
					.disabled(to < from || label.trimmingCharacters(in: .whitespaces).isEmpty)
				}
			}
		}
		.presentationDetents([.large])
		.task {
			from = Double(min(taken.map { Int($0.to) + 1 }.max() ?? 0, 255))
		}
	}
}
