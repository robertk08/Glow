import SwiftData
import SwiftUI

struct StoreView: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.dismiss) private var dismiss
	@Environment(\.modelContext) private var context
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	@Query(sort: \FixtureGroup.sortIndex) private var groups: [FixtureGroup]
	
	@Bindable var recording: Recording
	
	private let lightColumns = [GridItem(.adaptive(minimum: 92), spacing: 10)]
	private let featureColumns = [GridItem(.adaptive(minimum: 132), spacing: 8)]
	
	var body: some View {
		let levels = recording.levels
		
		NavigationStack {
			Form {
				Section {
					TextField(recording.isScene ? "Name" : "Cue Name", text: $recording.name)
						.autocorrectionDisabled()
						.font(.title3.weight(.semibold))
				}
				
				Section {
					ScrollView(.horizontal) {
						HStack(spacing: 8) {
							Button("All", systemImage: "circle.grid.3x3.fill") {
								recording.lights = recording.everyone
							}
							
							if !recording.changed.isEmpty {
								Button("Changed", systemImage: "pencil.and.outline") {
									recording.lights = recording.changed
								}
							}
							
							if !recording.selected.isEmpty {
								Button("Selected", systemImage: "checkmark.circle") {
									recording.lights = recording.selected
								}
							}
							
							ForEach(groups) { group in
								Toggle(isOn: Binding { recording.includes(group.members) } set: { _ in recording.toggle(group.members) }) {
									Label(group.name, systemImage: group.symbol)
								}
								.toggleStyle(.button)
								.tint(group.tint.color ?? .accentColor)
							}
							
							Button("None", systemImage: "circle.dashed") {
								recording.lights = []
							}
						}
						.font(.subheadline)
						.buttonStyle(.glass)
						.buttonBorderShape(.capsule)
						.padding(.vertical, 2)
					}
					.scrollIndicators(.hidden)
					.listRowInsets(.init(top: 8, leading: 0, bottom: 8, trailing: 0))
					.contentMargins(.horizontal, 16, for: .scrollContent)
					
					LazyVGrid(columns: lightColumns, spacing: 10) {
						ForEach(fixtures) { fixture in
							LightChip(fixture: fixture, isIncluded: recording.lights.contains(fixture.identifier), isChanged: recording.changed.contains(fixture.identifier))
								.onTapGesture {
									recording.toggle([fixture])
								}
						}
					}
					.padding(.vertical, 4)
				} header: {
					Text("Lights")
				} footer: {
					Text("Tap a light to take it in or out. A dot marks a light you changed.")
				}
				
				Section {
					Picker("Store", selection: $recording.keepsEverything) {
						Text("Changes").tag(false)
						Text("Everything").tag(true)
					}
					.pickerStyle(.segmented)
					.listRowSeparator(.hidden)
					
					LazyVGrid(columns: featureColumns, spacing: 8) {
						ForEach(FeatureGroup.allCases) { feature in
							Toggle(isOn: Binding { recording.features.contains(feature) } set: { _ in recording.toggle(feature) }) {
								Label(feature.name, systemImage: feature.symbol)
									.font(.subheadline.weight(.medium))
							}
							.toggleStyle(.button)
							.buttonStyle(.glass)
							.buttonBorderShape(.capsule)
							.tint(recording.features.contains(feature) ? Color.accentColor : nil)
						}
					}
					.padding(.vertical, 4)
					
					if recording.isInto {
						Toggle("Replace What the Cue Holds", isOn: $recording.replaces)
					}
				} header: {
					Text("What to Store")
				} footer: {
					Text(recording.keepsEverything ? "Every channel of these lights, as they are now." : "Only the channels you changed since they were last stored, so the cues before keep the rest.")
				}
				
				Section("Timing") {
					SecondsPicker(title: "Fade", seconds: $recording.fade, zero: "Snap")
				}
			}
			.navigationTitle(recording.title)
			.navigationSubtitle(levels.isEmpty ? "Nothing to store yet" : "\(levels.lights.count == 1 ? "1 light" : "\(levels.lights.count) lights"), \(levels.slotCount == 1 ? "1 channel" : "\(levels.slotCount) channels")")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button(role: .cancel) {
						dismiss()
					}
				}
				
				ToolbarItem(placement: .confirmationAction) {
					Button("Store", role: .confirm) {
						recording.store(context: context)
						dismiss()
					}
					.disabled(!recording.isReady)
				}
			}
			.sensoryFeedback(.selection, trigger: recording.lights)
		}
	}
}

private struct LightChip: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	
	let fixture: Fixture
	let isIncluded: Bool
	let isChanged: Bool
	
	var body: some View {
		let programmer = Programmer(fixture: fixture, library: library, console: console)
		let isOn = programmer?.isOn ?? false
		
		VStack(spacing: 6) {
			Image(systemName: fixture.symbol(library.type(fixture.typeID)))
				.font(.body)
				.foregroundStyle(isOn ? programmer?.displayInk ?? .white : .secondary)
				.frame(width: 34, height: 34)
				.background(isOn ? programmer?.glow ?? .accentColor : Color(.tertiarySystemFill), in: .circle)
				.overlay(alignment: .topTrailing) {
					Circle()
						.fill(.orange)
						.frame(width: 9, height: 9)
						.opacity(isChanged ? 1 : 0)
				}
			
			Text(fixture.name)
				.font(.caption)
				.lineLimit(1)
				.minimumScaleFactor(0.8)
		}
		.frame(maxWidth: .infinity)
		.padding(.vertical, 10)
		.padding(.horizontal, 6)
		.glassEffect(.regular.tint(isIncluded ? Color.accentColor.opacity(0.35) : nil).interactive(), in: .rect(cornerRadius: 16, style: .continuous))
		.opacity(isIncluded ? 1 : 0.55)
		.contentShape(.rect(cornerRadius: 16, style: .continuous))
		.accessibilityElement(children: .combine)
		.accessibilityAddTraits(.isButton)
		.accessibilityAddTraits(isIncluded ? .isSelected : [])
	}
}
