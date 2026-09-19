import SwiftData
import SwiftUI

struct FixtureTypeEditor: View {
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.modelContext) private var context
	@Environment(\.dismiss) private var dismiss
	
	@Query private var stored: [StoredFixtureType]
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	@State private var draft: FixtureType
	@State private var index = 0
	
	let original: FixtureType?
	
	init(type: FixtureType? = nil) {
		original = type
		_draft = State(initialValue: type ?? FixtureType(id: "", model: "", modes: [FixtureType.Mode(name: "1 channel", channels: [FixtureChannel(offset: 1, attribute: .dimmer)])]))
	}
	
	var body: some View {
		let mode = draft.modes[min(index, draft.modes.count - 1)]
		let forks = original.map { first in library.builtIn.contains { $0.id == first.id } } ?? false
		
		return NavigationStack {
			Form {
				Section {
					TextField("Model", text: $draft.model)
						.autocorrectionDisabled()
					
					TextField("Manufacturer", text: $draft.manufacturer)
						.autocorrectionDisabled()
				} footer: {
					Text(forks ? "Glow keeps the built-in fixture and saves yours beside it. Lights already patched to it move over to your version." : "Read the channel list off the fixture's manual and copy it in order. A fixture built here behaves exactly like one Glow ships.")
				}
				
				Section("Icon") {
					AppearancePicker(symbol: $draft.symbol)
				}
				
				if draft.modes.count > 1 {
					Section {
						Picker("Mode", selection: $index) {
							ForEach(draft.modes.indices, id: \.self) { position in
								Text(draft.modes[position].name).tag(position)
							}
						}
					} footer: {
						Text("Each mode is a different channel layout the same fixture can be switched to. Patching picks one.")
					}
				}
				
				Section {
					ForEach($draft.modes[min(index, draft.modes.count - 1)].channels) { $channel in
						NavigationLink(value: channel.offset) {
							LabeledContent {
								Text(channel.addressLabel)
									.monospacedDigit()
									.foregroundStyle(.secondary)
							} label: {
								VStack(alignment: .leading, spacing: 2) {
									Text(channel.name)
									
									Text(channel.summary)
										.font(.caption)
										.foregroundStyle(.secondary)
								}
							}
						}
					}
					.onDelete { offsets in
						draft.modes[index].channels.remove(atOffsets: offsets)
						draft.modes[index].renumber()
					}
					.onMove { source, destination in
						draft.modes[index].channels.move(fromOffsets: source, toOffset: destination)
						draft.modes[index].renumber()
					}
					
					Button("Add Channel", systemImage: "plus") {
						draft.modes[index].channels.append(FixtureChannel(offset: mode.width + 1, attribute: .custom))
					}
				} header: {
					Text("Channels")
				} footer: {
					Text("This mode uses ^[\(mode.width) address](inflect: true).")
				}
				
				if mode.mixesWithFlags {
					Section {
						Toggle("Subtractive CMY", isOn: Binding { draft.mixing == .subtractive } set: { draft.mixing = $0 ? .subtractive : .additive })
					} footer: {
						Text("On for a head that puts cyan, magenta and yellow flags in front of a white lamp, where zero means the flag is out of the beam. Off for a fixture whose cyan, magenta and yellow are their own LEDs.")
					}
				}
				
				if mode.movesHead {
					Section("Movement") {
						TextField("Pan range in degrees", value: $draft.panDegrees, format: .number)
							.keyboardType(.decimalPad)
						
						TextField("Tilt range in degrees", value: $draft.tiltDegrees, format: .number)
							.keyboardType(.decimalPad)
						
						Toggle("Invert Pan", isOn: $draft.invertsPan)
						Toggle("Invert Tilt", isOn: $draft.invertsTilt)
					}
				}
			}
			.navigationTitle(original == nil ? "Build a Fixture" : "Edit Fixture")
			.navigationBarTitleDisplayMode(.inline)
			.navigationDestination(for: Int.self) { offset in
				if let position = draft.modes[index].channels.firstIndex(where: { $0.offset == offset }) {
					ChannelEditor(channel: $draft.modes[index].channels[position])
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
						draft.model = draft.model.trimmingCharacters(in: .whitespaces)
						draft.manufacturer = draft.manufacturer.trimmingCharacters(in: .whitespaces)
						library.adopt(draft, replacing: original, among: fixtures, stored: stored, context: context)
						dismiss()
					}
					.disabled(draft.model.trimmingCharacters(in: .whitespaces).isEmpty || mode.channels.isEmpty)
				}
			}
		}
	}
}
