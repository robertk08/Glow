import SwiftData
import SwiftUI

struct FixtureEditView: View {
	@Query(sort: \FixtureGroup.sortIndex) private var groups: [FixtureGroup]
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.modelContext) private var context
	@Environment(\.dismiss) private var dismiss
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	@Bindable var fixture: Fixture
	
	private var profile: FixtureProfile? { library.profile(fixture.profileID) }
	
	private var overlapping: [Fixture] {
		let range = fixture.range(profile)
		return fixtures.filter {
			$0.persistentModelID != fixture.persistentModelID
				&& $0.range(library.profile($0.profileID)).overlaps(range)
		}
	}
	
	var body: some View {
		Form {
			Section {
				TextField("Name", text: $fixture.name)
			}
			
			Section("Icon") {
				IconPicker(symbols: FixtureSymbol.all, symbol: Binding { fixture.symbol(profile) } set: { fixture.symbolOverride = $0 })
				
				Picker("Colour", selection: $fixture.tint) {
					ForEach(FixtureTint.allCases) { tint in
						Text(tint.rawValue.capitalized).tag(tint)
					}
				}
			}
			
			if !groups.isEmpty {
				Section("Group") {
					Picker("Group", selection: $fixture.group) {
						Text("None").tag(FixtureGroup?.none)
						ForEach(groups) { group in
							Text(group.name).tag(FixtureGroup?.some(group))
						}
					}
					.labelsHidden()
				}
			}
			
			Section {
				Stepper(value: $fixture.address, in: DMXAddress.range) {
					LabeledContent("Address", value: "\(fixture.address)")
				}
				
				if let profile {
					LabeledContent("Channels", value: "\(profile.channelCount)")
					LabeledContent("Fixture", value: profile.name)
				}
			} footer: {
				if !overlapping.isEmpty {
					Text("Shares channels with \(overlapping.map(\.name).formatted(.list(type: .and))). They will move together.")
				}
			}
			
			Section {
				Button("Remove Light", role: .destructive) {
					context.delete(fixture)
					dismiss()
				}
			}
		}
		.navigationTitle(fixture.name)
		.navigationBarTitleDisplayMode(.inline)
	}
}
