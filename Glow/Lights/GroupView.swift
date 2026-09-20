import SwiftData
import SwiftUI

struct GroupView: View {
	@Environment(\.modelContext) private var context
	@Environment(\.dismiss) private var dismiss
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	@Bindable var group: FixtureGroup
	
	@State private var isNew = false
	@State private var named = ""
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
				
				Section("Lights") {
					ForEach(fixtures) { fixture in
						Toggle(fixture.name, isOn: Binding { fixture.belongs(to: group) } set: { fixture.belong(to: group, $0) })
					}
				}
				
				Section("Icon") {
					AppearancePicker(symbol: Binding { group.symbol } set: { group.symbolOverride = $0 }, tint: $group.tint)
				}
				
				if !isNew {
					Section {
						Button("Delete Group", role: .destructive) {
							isDeleting = true
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
			.navigationTitle(isNew ? "New Group" : "Edit Group")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button("Done") {
						group.name = group.name.trimmingCharacters(in: .whitespaces)
						dismiss()
					}
					.disabled(group.name.trimmingCharacters(in: .whitespaces).isEmpty)
				}
			}
			.task {
				isNew = group.name.isEmpty
				isNaming = isNew
				named = group.name
			}
			.onDisappear {
				group.name = group.name.trimmingCharacters(in: .whitespaces)
				guard group.name.isEmpty else { return }
				
				if isNew {
					context.delete(group)
				} else {
					group.name = named
				}
			}
		}
	}
}
