import SwiftData
import SwiftUI

struct StoreView: View {
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.dismiss) private var dismiss
	@Environment(\.modelContext) private var context
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	@Query(sort: \FixtureGroup.sortIndex) private var groups: [FixtureGroup]
	
	@Bindable var recording: Recording
	
	private let aspects = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
	
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
					LazyVGrid(columns: aspects, spacing: 8) {
						ForEach(FeatureGroup.allCases) { feature in
							ChoiceTile(name: feature.name, symbol: feature.symbol, tint: .accentColor, isOn: recording.features.contains(feature)) {
								recording.toggle(feature)
							}
						}
					}
					.listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
				} header: {
					Text("Store")
				}
				
				Section {
					if !groups.isEmpty {
						LazyVGrid(columns: aspects, spacing: 8) {
							ForEach(groups) { group in
								ChoiceTile(name: group.name, symbol: group.symbol, tint: group.tint.color ?? .accentColor, isOn: recording.contains(group)) {
									recording.toggle(group)
								}
							}
						}
						.listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
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

private struct ChoiceTile: View {
	let name: String
	let symbol: String
	let tint: Color
	let isOn: Bool
	let toggle: () -> Void
	
	var body: some View {
		Button(action: toggle) {
			VStack(spacing: 6) {
				Image(systemName: symbol)
					.font(.title3)
					.frame(height: 26)
				
				Text(name)
					.font(.caption.weight(.medium))
					.lineLimit(1)
					.minimumScaleFactor(0.8)
			}
			.foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
			.frame(maxWidth: .infinity, minHeight: 64)
			.background(isOn ? tint : Color(.tertiarySystemFill), in: .rect(cornerRadius: 14, style: .continuous))
			.contentShape(.rect(cornerRadius: 14, style: .continuous))
		}
		.buttonStyle(.plain)
		.accessibilityAddTraits(isOn ? .isSelected : [])
		.animation(.snappy(duration: 0.2), value: isOn)
	}
}
