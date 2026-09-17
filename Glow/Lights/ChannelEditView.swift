import SwiftUI

struct ChannelEditView: View {
	@Binding var channel: CustomChannel
	
	let number: Int
	
	@State private var isAddingRange = false
	@State private var from = 0.0
	@State private var to = 255.0
	@State private var label = ""
	
	var body: some View {
		Form {
			Section {
				Picker("Does", selection: $channel.role) {
					ForEach(ChannelRole.allCases) { role in
						Text(role.name).tag(role)
					}
				}
				
				TextField(channel.role.name, text: $channel.name)
			} header: {
				Text("Channel \(number)")
			} footer: {
				Text("Leave the name empty and the programmer shows \(channel.role.name).")
			}
			
			Section {
				Toggle("16-bit fine", isOn: $channel.isFine)
			} footer: {
				Text("On when this channel is the fine half of the channel above it, which has to carry the same job.")
			}
			
			Section {
				LabeledContent("Starts at", value: "\(channel.defaultValue)")
					.monospacedDigit()
				
				Slider(value: Binding { Double(channel.defaultValue) } set: { channel.defaultValue = UInt8($0.rounded()) }, in: 0...255) {
					Text("Starts at")
				}
			} footer: {
				Text("Where the channel sits when the light is patched and where Reset to Defaults puts it back.")
			}
			
			Section {
				ForEach(channel.ranges) { range in
					LabeledContent {
						Text(range.label)
							.multilineTextAlignment(.trailing)
					} label: {
						Text("\(range.from)–\(range.to)")
							.monospacedDigit()
							.foregroundStyle(.secondary)
					}
				}
				.onDelete { channel.ranges.remove(atOffsets: $0) }
				
				Button("Add Range", systemImage: "plus") {
					from = Double(min(channel.ranges.map(\.to).max().map { Int($0) + 1 } ?? 0, 255))
					to = 255
					label = ""
					isAddingRange = true
				}
			} header: {
				Text("Ranges")
			} footer: {
				Text("A channel with ranges gets a named picker in the programmer. One without gets a plain slider on the raw value.")
			}
		}
		.navigationTitle(channel.title)
		.navigationBarTitleDisplayMode(.inline)
		.sheet(isPresented: $isAddingRange) {
			RangeSheet(from: $from, to: $to, label: $label) { range in
				channel.ranges.append(range)
				channel.ranges.sort { $0.from < $1.from }
			}
		}
	}
}

private struct RangeSheet: View {
	@Environment(\.dismiss) private var dismiss
	
	@Binding var from: Double
	@Binding var to: Double
	@Binding var label: String
	
	let save: (ChannelRange) -> Void
	
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
			}
			.navigationTitle("Add Range")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button(role: .cancel) { dismiss() }
				}
				
				ToolbarItem(placement: .confirmationAction) {
					Button(role: .confirm) {
						save(ChannelRange(from: UInt8(from), to: UInt8(to), label: label.trimmingCharacters(in: .whitespaces)))
						dismiss()
					}
					.disabled(to < from || label.trimmingCharacters(in: .whitespaces).isEmpty)
				}
			}
		}
		.presentationDetents([.medium])
	}
}
