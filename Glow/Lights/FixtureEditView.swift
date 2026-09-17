import SwiftData
import SwiftUI

struct FixtureEditView: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.modelContext) private var context
	@Environment(\.dismiss) private var dismiss
	@Query(sort: \FixtureGroup.sortIndex) private var groups: [FixtureGroup]
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	@Bindable var fixture: Fixture
	
	private var profile: FixtureProfile? { library.profile(fixture.profileID) }
	
	var body: some View {
		Form {
			Section {
				TextField("Name", text: $fixture.name)
			}
			
			Section("Icon") {
				AppearancePicker(symbols: FixtureSymbol.all, symbol: Binding { fixture.symbol(profile) } set: { fixture.symbolOverride = $0 }, tint: $fixture.tint)
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
						.monospacedDigit()
				}
				
				if let profile {
					LabeledContent("Channels", value: "\(profile.channelCount)")
					LabeledContent("Fixture", value: profile.name)
				}
			} header: {
				Text("Patch")
			} footer: {
				let overlapping = Fixture.overlapping(fixture, among: fixtures, library: library)
				
				if !overlapping.isEmpty {
					Text("Shares channels with \(overlapping.map(\.name).formatted(.list(type: .and))). They will move together.")
				}
			}
			
			Section {
				Button("Remove Light", role: .destructive) {
					console.remove(fixture, context: context, library: library)
					dismiss()
				}
			} footer: {
				Text("Its channels go back to zero on the way out.")
			}
		}
		.navigationTitle(fixture.name)
		.navigationBarTitleDisplayMode(.inline)
	}
}
