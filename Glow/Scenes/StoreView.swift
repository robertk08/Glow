import SwiftData
import SwiftUI

struct StoreView: View {
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.dismiss) private var dismiss
	@Environment(\.modelContext) private var context
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	@Query(sort: \FixtureGroup.sortIndex) private var groups: [FixtureGroup]
	
	@Bindable var recording: Recording
	
	var body: some View {
		NavigationStack {
			Form {
				if recording.isNew {
					Section {
						TextField(recording.title, text: $recording.label, axis: .vertical)
							.lineLimit(1...3)
							.autocorrectionDisabled()
					}
					
					Section {
						CueTiming(fade: $recording.fade, delay: $recording.delay, follow: $recording.follow)
					}
				}
				
				Section {
					ScrollView(.horizontal) {
						HStack(spacing: 8) {
							ForEach(FeatureGroup.allCases) { feature in
								Toggle(isOn: Binding { recording.features.contains(feature) } set: { _ in recording.toggle(feature) }) {
									Label(feature.name, systemImage: feature.symbol)
										.font(.subheadline)
								}
							}
						}
						.padding(.vertical, 4)
					}
					.contentMargins(.horizontal, 20, for: .scrollContent)
					.scrollIndicators(.hidden)
					.toggleStyle(.button)
					.buttonStyle(.glass)
					.buttonBorderShape(.capsule)
					.listRowBackground(Color.clear)
					.listRowInsets(EdgeInsets())
				} header: {
					Text("Store")
				}
				
				if !groups.isEmpty {
					Section {
						ScrollView(.horizontal) {
							HStack(spacing: 8) {
								ForEach(groups) { group in
									Toggle(isOn: Binding { recording.contains(group) } set: { _ in recording.toggle(group) }) {
										Label(group.name, systemImage: group.symbol)
											.font(.subheadline)
									}
									.tint(group.tint.color ?? .accentColor)
								}
							}
							.padding(.vertical, 4)
						}
						.contentMargins(.horizontal, 20, for: .scrollContent)
						.scrollIndicators(.hidden)
						.toggleStyle(.button)
						.buttonStyle(.glass)
						.buttonBorderShape(.capsule)
						.listRowBackground(Color.clear)
						.listRowInsets(EdgeInsets())
					} header: {
						Text("Groups")
					}
				}
				
				Section {
					ForEach(fixtures) { fixture in
						Toggle(isOn: Binding { recording.lights.contains(fixture.identifier) } set: { _ in recording.toggle(fixture) }) {
							Label(fixture.name, systemImage: fixture.symbol(library.type(fixture.typeID)))
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
			}
			.navigationTitle(recording.title)
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button(role: .cancel) {
						dismiss()
					}
				}
				
				ToolbarItem(placement: .confirmationAction) {
					Button(recording.isNew ? "Store" : "Update", role: .confirm) {
						recording.store(context: context)
						dismiss()
					}
					.disabled(!recording.isReady)
				}
			}
			.sensoryFeedback(.selection, trigger: recording.lights)
			.sensoryFeedback(.selection, trigger: recording.features)
		}
	}
}
