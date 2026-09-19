import SwiftData
import SwiftUI

struct CustomFixtureView: View {
	@Environment(\.modelContext) private var context
	@Environment(\.dismiss) private var dismiss
	
	@Query private var customProfiles: [CustomProfile]
	@State private var draft: CustomProfile
	let profile: FixtureProfile?
	
	init(profile: FixtureProfile? = nil) {
		self.profile = profile
		_draft = State(initialValue: CustomProfile(profile: profile))
	}

	var body: some View {
		NavigationStack {
			Form {
				Section {
					TextField("Name", text: $draft.name)
						.autocorrectionDisabled()
				} footer: {
					Text("Read the channel list off the fixture's manual and copy it in order. A fixture built here behaves exactly like one Glow ships.")
				}
				
				Section("Details") {
					TextField("Manufacturer", text: $draft.manufacturer)
					TextField("Mode", text: $draft.mode)
				}
				
				Section("Movement") {
					TextField("Pan range in degrees", value: $draft.panDegrees, format: .number)
						.keyboardType(.decimalPad)
					TextField("Tilt range in degrees", value: $draft.tiltDegrees, format: .number)
						.keyboardType(.decimalPad)
					Toggle("Invert Pan", isOn: $draft.invertsPan)
					Toggle("Invert Tilt", isOn: $draft.invertsTilt)
				}
				
				Section("Icon") {
					AppearancePicker(symbol: $draft.symbol)
				}
				
				Section {
					ForEach($draft.channelList) { $channel in
						NavigationLink(value: channel.id) {
							LabeledContent {
								Text("\((draft.channelList.firstIndex { $0.id == channel.id } ?? 0) + 1)")
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
					.onDelete { draft.channelList.remove(atOffsets: $0) }
					.onMove { draft.channelList.move(fromOffsets: $0, toOffset: $1) }
					
					Button("Add Channel", systemImage: "plus") {
						draft.channelList.append(CustomChannel(role: .custom))
					}
				} header: {
					Text("Channels")
				} footer: {
					Text("This fixture uses ^[\(draft.channelList.count) address](inflect: true).")
				}
				
				if draft.mixesWithFlags {
					Section {
						Toggle("Subtractive CMY", isOn: $draft.isSubtractive)
					} footer: {
						Text("On for a head that puts cyan, magenta and yellow flags in front of a white lamp, where zero means the flag is out of the beam. Off for a fixture whose cyan, magenta and yellow are their own LEDs.")
					}
				}
			}
			.navigationTitle(profile == nil ? "Build a Fixture" : "Edit Fixture")
			.navigationBarTitleDisplayMode(.inline)
			.navigationDestination(for: CustomChannel.ID.self) { id in
				if let index = draft.channelList.firstIndex(where: { $0.id == id }) {
					ChannelEditView(channel: $draft.channelList[index], number: index + 1)
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
						draft.name = draft.name.trimmingCharacters(in: .whitespaces)
						if let existing = customProfiles.first(where: { $0.identifier == draft.identifier }) {
							existing.adopt(draft)
						} else {
							draft.identifier = "custom-\(UUID().uuidString)"
							context.insert(draft)
						}
						dismiss()
					}
					.disabled(!draft.canSave)
				}
			}
		}
	}
}
