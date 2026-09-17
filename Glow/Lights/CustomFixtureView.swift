import SwiftData
import SwiftUI

struct CustomFixtureView: View {
	@Environment(\.modelContext) private var context
	@Environment(\.dismiss) private var dismiss
	
	@State private var name = ""
	@State private var symbol = "lightbulb"
	@State private var isSubtractive = false
	@State private var channels: [CustomChannel] = [CustomChannel(role: .intensity)]
	@State private var editing: CustomChannel.ID?
	
	private var mixesWithFlags: Bool {
		Set(Emitter.flags).isSubset(of: Set(channels.filter { !$0.isFine }.map(\.role)))
	}
	
	var body: some View {
		NavigationStack {
			Form {
				Section {
					TextField("Name", text: $name)
						.autocorrectionDisabled()
				} footer: {
					Text("Read the channel list off the fixture's manual and copy it in order. A fixture built here behaves exactly like one Glow ships.")
				}
				
				Section("Icon") {
					AppearancePicker(symbols: FixtureSymbol.all, symbol: $symbol)
				}
				
				Section {
					ForEach($channels) { $channel in
						NavigationLink(value: channel.id) {
							LabeledContent {
								Text("\((channels.firstIndex { $0.id == channel.id } ?? 0) + 1)")
									.monospacedDigit()
									.foregroundStyle(.secondary)
							} label: {
								VStack(alignment: .leading, spacing: 2) {
									Text(channel.title)
									Text(channel.summary)
										.font(.caption)
										.foregroundStyle(.secondary)
								}
							}
						}
					}
					.onDelete { channels.remove(atOffsets: $0) }
					.onMove { channels.move(fromOffsets: $0, toOffset: $1) }
					
					Button("Add Channel", systemImage: "plus") {
						channels.append(CustomChannel(role: .custom))
					}
				} header: {
					Text("Channels")
				} footer: {
					Text("This fixture uses ^[\(channels.count) address](inflect: true).")
				}
				
				if mixesWithFlags {
					Section {
						Toggle("Subtractive CMY", isOn: $isSubtractive)
					} footer: {
						Text("On for a head that puts cyan, magenta and yellow flags in front of a white lamp, where zero means the flag is out of the beam. Off for a fixture whose cyan, magenta and yellow are their own LEDs.")
					}
				}
			}
			.navigationTitle("Build a Fixture")
			.navigationBarTitleDisplayMode(.inline)
			.navigationDestination(for: CustomChannel.ID.self) { id in
				if let index = channels.firstIndex(where: { $0.id == id }) {
					ChannelEditView(channel: $channels[index], number: index + 1)
				}
			}
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button(role: .close) { dismiss() }
				}
				
				ToolbarItem(placement: .topBarTrailing) {
					EditButton()
				}
				
				ToolbarItem(placement: .confirmationAction) {
					Button("Save") {
						context.insert(CustomProfile(name: name.trimmingCharacters(in: .whitespaces), symbol: symbol, channels: channels, isSubtractive: isSubtractive && mixesWithFlags))
						dismiss()
					}
					.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || channels.isEmpty)
				}
			}
		}
	}
}
