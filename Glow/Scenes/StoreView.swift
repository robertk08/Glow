import SwiftData
import SwiftUI

struct StoreView: View {
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.dismiss) private var dismiss
	@Environment(\.modelContext) private var context
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	@Query(sort: \FixtureGroup.sortIndex) private var groups: [FixtureGroup]
	
	@Bindable var recording: Recording
	
	private let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]
	
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
					LazyVGrid(columns: columns, spacing: 8) {
						ForEach(FeatureGroup.allCases) { feature in
							Toggle(isOn: Binding { recording.features.contains(feature) } set: { _ in recording.toggle(feature) }) {
								HStack(spacing: 6) {
									Image(systemName: feature.symbol)
									
									Text(feature.name)
								}
								.font(.subheadline)
								.lineLimit(1)
								.minimumScaleFactor(0.8)
								.frame(maxWidth: .infinity)
							}
						}
					}
					.toggleStyle(.button)
					.buttonStyle(.glass)
					.buttonBorderShape(.capsule)
					.padding(.vertical, 4)
				} header: {
					Text("Store")
				}
				
				Section {
					if !groups.isEmpty {
						LazyVGrid(columns: columns, spacing: 8) {
							ForEach(groups) { group in
								Toggle(isOn: Binding { recording.contains(group) } set: { _ in recording.toggle(group) }) {
									HStack(spacing: 6) {
										Image(systemName: group.symbol)
										
										Text(group.name)
									}
									.font(.subheadline)
									.lineLimit(1)
									.minimumScaleFactor(0.8)
									.frame(maxWidth: .infinity)
								}
								.tint(group.tint.color ?? .accentColor)
							}
						}
						.toggleStyle(.button)
						.buttonStyle(.glass)
						.buttonBorderShape(.capsule)
						.padding(.vertical, 4)
					}
					
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
					Button(role: .close) {
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
