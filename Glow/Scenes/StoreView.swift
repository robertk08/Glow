import SwiftData
import SwiftUI

struct StoreView: View {
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.dismiss) private var dismiss
	@Environment(\.modelContext) private var context
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	@Bindable var recording: Recording
	
	var body: some View {
		NavigationStack {
			Form {
				Section {
					TextField("Name or short description", text: $recording.label, axis: .vertical)
						.lineLimit(1...3)
						.autocorrectionDisabled()
				}
				
				Section {
					ForEach(fixtures) { fixture in
						Toggle(isOn: Binding { recording.lights.contains(fixture.identifier) } set: { _ in recording.toggle(fixture) }) {
							Label {
								Text(fixture.name)
								
								if recording.changed.contains(fixture.identifier) {
									Text("Changed")
								} else if recording.lit.contains(fixture.identifier) {
									Text("On")
								}
							} icon: {
								Image(systemName: fixture.symbol(library.type(fixture.typeID)))
							}
						}
					}
				} header: {
					HStack {
						Text("Lights")
						
						Spacer()
						
						Button(recording.lights.count == fixtures.count ? "None" : "All") {
							recording.lights = recording.lights.count == fixtures.count ? [] : Set(fixtures.map(\.identifier))
						}
						.font(.subheadline)
						.textCase(nil)
					}
				}
				
				Section {
					ForEach(FeatureGroup.allCases) { feature in
						Toggle(isOn: Binding { recording.features.contains(feature) } set: { _ in recording.toggle(feature) }) {
							Label(feature.name, systemImage: feature.symbol)
						}
					}
				} header: {
					Text("Store")
				} footer: {
					Text(recording.summary)
				}
				
				Section {
					Stepper(value: $recording.fade, in: 0...600, step: 0.5) {
						LabeledContent("Fade", value: Cue.seconds(recording.fade))
							.monospacedDigit()
					}
				}
			}
			.navigationTitle(recording.title)
			.navigationSubtitle(recording.place)
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
