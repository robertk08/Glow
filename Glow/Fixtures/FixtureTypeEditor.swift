import SwiftData
import SwiftUI

struct FixtureTypeEditor: View {
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.modelContext) private var context
	@Environment(\.dismiss) private var dismiss
	
	@Query private var stored: [StoredFixtureType]
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	@State private var draft: FixtureType
	
	let original: FixtureType?
	
	init(type: FixtureType? = nil) {
		original = type
		_draft = State(initialValue: type ?? FixtureType(id: "", model: "", channels: [FixtureChannel(offset: 1, attribute: .dimmer)]))
	}
	
	var body: some View {
		let forks = original.map { first in library.builtIn.contains { $0.id == first.id } } ?? false
		
		NavigationStack {
			Form {
				Section {
					TextField("Model", text: $draft.model)
						.autocorrectionDisabled()
					
					TextField("Manufacturer", text: $draft.manufacturer)
						.autocorrectionDisabled()
					
					TextField("Mode", text: $draft.mode)
						.autocorrectionDisabled()
				}
				
				Section("Icon") {
					AppearancePicker(symbol: $draft.symbol)
				}
				
				Section {
					ForEach($draft.channels) { $channel in
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
						draft.channels.remove(atOffsets: offsets)
						draft.renumber()
					}
					.onMove { source, destination in
						draft.channels.move(fromOffsets: source, toOffset: destination)
						draft.renumber()
					}
					
					Button("Add Channel", systemImage: "plus") {
						draft.channels.append(FixtureChannel(offset: draft.channelCount + 1, attribute: .custom))
					}
				} header: {
					Text("Channels")
				}
				
				if draft.mixesWithFlags {
					Section {
						Toggle("Subtractive CMY", isOn: Binding { draft.mixing == .subtractive } set: { draft.mixing = $0 ? .subtractive : .additive })
					}
				}
				
				if draft.movesHead {
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
				if let position = draft.channels.firstIndex(where: { $0.offset == offset }) {
					ChannelEditor(channel: $draft.channels[position], others: draft.channels)
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
					.disabled(draft.model.trimmingCharacters(in: .whitespaces).isEmpty || draft.channels.isEmpty)
				}
			}
		}
	}
}
