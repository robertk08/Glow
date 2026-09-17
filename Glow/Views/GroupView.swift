import SwiftData
import SwiftUI

struct GroupView: View {
	@Environment(\.modelContext) private var context
	@Environment(\.dismiss) private var dismiss
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	@Bindable var group: FixtureGroup
	
	var body: some View {
		Form {
			Section {
				TextField("Name", text: $group.name)
			}
			
			Section("Icon") {
				IconPicker(symbols: FixtureSymbol.groups, symbol: Binding { group.symbol } set: { group.symbolOverride = $0 })
				
				Picker("Colour", selection: $group.tint) {
					ForEach(FixtureTint.allCases) { tint in
						Text(tint.rawValue.capitalized).tag(tint)
					}
				}
			}
			
			Section("Lights") {
				ForEach(fixtures) { fixture in
					Button {
						fixture.group = fixture.group == group ? nil : group
					} label: {
						LabeledContent {
							if fixture.group == group {
								Image(systemName: "checkmark")
									.foregroundStyle(.tint)
							}
						} label: {
							Text(fixture.name)
						}
						.contentShape(.rect)
					}
					.buttonStyle(.plain)
				}
			}
			
			Section {
				Button("Delete Group", role: .destructive) {
					context.delete(group)
					dismiss()
				}
			}
		}
		.navigationTitle(group.name)
		.navigationBarTitleDisplayMode(.inline)
	}
}
