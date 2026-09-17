import SwiftData
import SwiftUI

struct CustomFixtureView: View {
	@Environment(\.modelContext) private var context
	@Environment(\.dismiss) private var dismiss
	
	@State private var name = ""
	@State private var symbol = "lightbulb"
	@State private var channels: [CustomChannel] = [CustomChannel(role: .intensity, name: "")]
	
	private let columns = [GridItem(.adaptive(minimum: 44), spacing: 12)]
	
	private var canSave: Bool {
		!name.trimmingCharacters(in: .whitespaces).isEmpty && !channels.isEmpty
	}
	
	var body: some View {
		NavigationStack {
			Form {
				Section {
					TextField("Name", text: $name)
						.autocorrectionDisabled()
				} footer: {
					Text("Anything with a DMX address can go here. Read the channel list off the fixture's manual and copy it in order.")
				}
				
				Section("Icon") {
					LazyVGrid(columns: columns, spacing: 12) {
						ForEach(FixtureSymbol.all, id: \.self) { option in
							Button {
								Haptic.feedback(.selection)
								symbol = option
							} label: {
								Image(systemName: option)
									.font(.title3)
									.frame(width: 44, height: 44)
									.background(symbol == option ? Color.accentColor.opacity(0.2) : .clear, in: .circle)
							}
							.buttonStyle(.plain)
						}
					}
					.padding(.vertical, 4)
				}
				
				Section {
					ForEach($channels) { $channel in
						VStack(alignment: .leading) {
							Picker("Does", selection: $channel.role) {
								ForEach(ChannelRole.allCases) { role in
									Text(role.name).tag(role)
								}
							}
							
							TextField(channel.role.name, text: $channel.name)
								.font(.caption)
								.foregroundStyle(.secondary)
						}
					}
					.onDelete { channels.remove(atOffsets: $0) }
					.onMove { channels.move(fromOffsets: $0, toOffset: $1) }
					
					Button("Add Channel", systemImage: "plus") {
						Haptic.feedback(.rigid)
						channels.append(CustomChannel(role: .custom, name: ""))
					}
				} header: {
					Text("Channels")
				} footer: {
					Text("Channel \(channels.count) is the last one, so this fixture uses \(channels.count) addresses.")
				}
			}
			.navigationTitle("Build a Fixture")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button(role: .close) { dismiss() }
				}
				
				ToolbarItem(placement: .confirmationAction) {
					Button("Save") {
						Haptic.feedback(.success)
						context.insert(CustomProfile(name: name.trimmingCharacters(in: .whitespaces), symbol: symbol, channels: channels))
						dismiss()
					}
					.disabled(!canSave)
				}
			}
		}
	}
}
