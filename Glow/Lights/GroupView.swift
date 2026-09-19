import SwiftData
import SwiftUI

struct GroupView: View {
	@Environment(\.modelContext) private var context
	@Environment(\.dismiss) private var dismiss
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	@Bindable var group: FixtureGroup
	
	@State private var isDeleting = false
	
	var body: some View {
		NavigationStack {
			Form {
				Section {
					TextField("Name", text: $group.name)
				}
				
				Section("Icon") {
					AppearancePicker(symbol: Binding { group.symbol } set: { group.symbolOverride = $0 }, tint: $group.tint)
				}
				
				Section {
					ForEach(fixtures) { fixture in
						Toggle(fixture.name, isOn: Binding { fixture.group == group } set: { fixture.group = $0 ? group : nil })
					}
				} header: {
					Text("Lights")
				}
				
				Section {
					Button("Delete Group", role: .destructive) {
						isDeleting = true
					}
				}
			}
			.navigationTitle(group.name)
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button("Done") { dismiss() }
				}
			}
			.confirmationDialog("Delete \(group.name)?", isPresented: $isDeleting, titleVisibility: .visible) {
				Button("Delete Group", role: .destructive) {
					context.delete(group)
					dismiss()
				}
			} message: {
				Text("The lights in it stay patched.")
			}
		}
	}
}
