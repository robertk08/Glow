import SwiftUI

struct FunctionEditor: View {
	@Binding var function: ChannelFunction
	
	var body: some View {
		Form {
			Section {
				TextField("What it does", text: $function.label)
					.autocorrectionDisabled()
			}
			
			Section {
				LabeledContent("From", value: "\(function.from)")
					.monospacedDigit()
				
				Slider(value: Binding { Double(function.from) } set: { function.from = UInt8(min($0.rounded(), Double(function.to))) }, in: 0...255) {
					Text("From")
				}
				
				LabeledContent("To", value: "\(function.to)")
					.monospacedDigit()
				
				Slider(value: Binding { Double(function.to) } set: { function.to = UInt8(max($0.rounded(), Double(function.from))) }, in: 0...255) {
					Text("To")
				}
			} header: {
				Text("Range")
			}
			
			Section {
				Picker("Control", selection: $function.kind) {
					Text("Setting").tag(ChannelFunction.Kind.setting)
					Text("Variable").tag(ChannelFunction.Kind.proportional)
				}
				
				Picker("Stands for", selection: $function.purpose) {
					Text("Nothing in particular").tag(ChannelFunction.Purpose?.none)
					Text("The dimmer").tag(ChannelFunction.Purpose?.some(.dim))
					Text("Fully open").tag(ChannelFunction.Purpose?.some(.open))
					Text("Blacked out").tag(ChannelFunction.Purpose?.some(.closed))
					Text("Hands color back to the mixer").tag(ChannelFunction.Purpose?.some(.release))
				}
				
				Toggle("Confirm Before Sending", isOn: $function.requiresConfirmation)
				
				Stepper(value: Binding { function.holdSeconds ?? 0 } set: { function.holdSeconds = $0 > 0 ? $0 : nil }, in: 0...60, step: 0.5) {
					LabeledContent("Hold", value: (function.holdSeconds ?? 0) == 0 ? "Until Changed" : "\((function.holdSeconds ?? 0).formatted()) s")
				}
			} header: {
				Text("Behavior")
			}
			
			Section {
				Picker("Reads in", selection: $function.unit) {
					Text("Raw value").tag(PhysicalUnit?.none)
					Text("Percent").tag(PhysicalUnit?.some(.percent))
					Text("Degrees").tag(PhysicalUnit?.some(.degrees))
					Text("Hertz").tag(PhysicalUnit?.some(.hertz))
					Text("Seconds").tag(PhysicalUnit?.some(.seconds))
					Text("Kelvin").tag(PhysicalUnit?.some(.kelvin))
					Text("RPM").tag(PhysicalUnit?.some(.rpm))
				}
				
				if function.unit != nil {
					TextField("At the start", value: $function.physicalFrom, format: .number)
						.keyboardType(.numbersAndPunctuation)
					
					TextField("At the end", value: $function.physicalTo, format: .number)
						.keyboardType(.numbersAndPunctuation)
				}
			} header: {
				Text("Real units")
			}
			
			Section("Color") {
				SwatchPicker(colors: $function.colors)
			}
			
			Section {
				ForEach($function.sets) { $set in
					NavigationLink {
						ChannelSetEditor(set: $set)
					} label: {
						LabeledContent {
							Text(set.label)
								.multilineTextAlignment(.trailing)
						} label: {
							HStack(spacing: 6) {
								if !set.swatch.isEmpty {
									Swatch(colors: set.swatch, size: 16)
								}
								
								Text("\(set.from)–\(set.to)")
									.monospacedDigit()
									.foregroundStyle(.secondary)
							}
						}
					}
				}
				.onDelete { function.sets.remove(atOffsets: $0) }
				
				Button("Add Slot", systemImage: "plus") {
					let start = function.sets.map { Int($0.to) + 1 }.max() ?? Int(function.from)
					function.sets.append(ChannelSet(from: UInt8(min(start, Int(function.to))), to: function.to, label: "Slot \(function.sets.count + 1)"))
				}
			} header: {
				Text("Slots")
			}
		}
		.navigationTitle(function.label.isEmpty ? "Range" : function.label)
		.navigationBarTitleDisplayMode(.inline)
	}
}

private struct ChannelSetEditor: View {
	@Binding var set: ChannelSet
	
	var body: some View {
		Form {
			Section {
				TextField("Name", text: $set.label)
					.autocorrectionDisabled()
			}
			
			Section("Range") {
				LabeledContent("From", value: "\(set.from)")
					.monospacedDigit()
				
				Slider(value: Binding { Double(set.from) } set: { set.from = UInt8(min($0.rounded(), Double(set.to))) }, in: 0...255) {
					Text("From")
				}
				
				LabeledContent("To", value: "\(set.to)")
					.monospacedDigit()
				
				Slider(value: Binding { Double(set.to) } set: { set.to = UInt8(max($0.rounded(), Double(set.from))) }, in: 0...255) {
					Text("To")
				}
			}
			
			Section("Color") {
				SwatchPicker(colors: $set.colors)
			}
		}
		.navigationTitle(set.label.isEmpty ? "Slot" : set.label)
		.navigationBarTitleDisplayMode(.inline)
	}
}
