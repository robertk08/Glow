import SwiftData
import SwiftUI

struct GroupView: View {
	@Environment(\.modelContext) private var context
	@Environment(\.dismiss) private var dismiss
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	@Bindable var group: FixtureGroup
	
	@State private var isDeleting = false
	@FocusState private var isNaming: Bool
	
	var body: some View {
		NavigationStack {
			Form {
				Section {
					TextField("Name", text: $group.name)
						.focused($isNaming)
						.autocorrectionDisabled()
						.submitLabel(.done)
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
			.navigationTitle(group.name.isEmpty ? "New Group" : group.name)
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button("Done") {
						group.name = group.name.trimmingCharacters(in: .whitespaces)
						dismiss()
					}
				}
			}
			.task {
				isNaming = group.name.isEmpty
			}
			.onDisappear {
				group.name = group.name.trimmingCharacters(in: .whitespaces)
				guard group.name.isEmpty, group.members.isEmpty else { return }
				context.delete(group)
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
