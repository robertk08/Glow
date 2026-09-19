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
	
	@State private var isRemoving = false
	
	private var type: FixtureType? { library.type(fixture.typeID) }
	
	var body: some View {
		Form {
			if type == nil {
				Section {
					Picker("Fixture", selection: $fixture.typeID) {
						Text("Not set").tag(fixture.typeID)
						
						ForEach(library.types) { option in
							Text(option.mode.isEmpty ? option.name : "\(option.name), \(option.mode)").tag(option.id)
						}
					}
				} header: {
					Label("Needs a Fixture", systemImage: "exclamationmark.triangle")
						.foregroundStyle(.orange)
				} footer: {
					Text("The definition this light was patched from is gone, so Glow cannot drive it. Point it at another one and it keeps its name, address and group.")
				}
			}
			
			Section {
				TextField("Name", text: $fixture.name)
			}
			
			Section("Icon") {
				AppearancePicker(symbol: Binding { fixture.symbol(type) } set: { fixture.symbolOverride = $0 })
			}
			
			if !groups.isEmpty {
				Section("Group") {
					Picker("Group", selection: $fixture.group) {
						Text("None").tag(FixtureGroup?.none)
						ForEach(groups) { group in
							Text(group.name).tag(FixtureGroup?.some(group))
						}
					}
				}
			}
			
			if type?.movesHead == true {
				Section {
					Toggle("Invert Pan", isOn: $fixture.invertsPan)
					Toggle("Invert Tilt", isOn: $fixture.invertsTilt)
				} header: {
					Text("Orientation")
				}
			}
			
			Section {
				Stepper(value: $fixture.address, in: DMXAddress.range) {
					LabeledContent("Address", value: "\(fixture.address)")
						.monospacedDigit()
				}
				
				if let type {
					LabeledContent("Channels", value: "\(type.channelCount)")
					
					NavigationLink {
						FixtureTypeView(type: type)
					} label: {
						LabeledContent("Fixture", value: type.name)
					}
				}
			} header: {
				Text("Patch")
			}
			
			Section {
				Button("Remove Light", role: .destructive) {
					isRemoving = true
				}
			}
		}
		.navigationTitle(fixture.name)
		.navigationBarTitleDisplayMode(.inline)
		.confirmationDialog("Remove \(fixture.name)?", isPresented: $isRemoving, titleVisibility: .visible) {
			Button("Remove Light", role: .destructive) {
				console.remove(fixture, context: context, library: library)
				dismiss()
			}
		} message: {
			Text("Its channels go back to zero and any scene holding it forgets it.")
		}
	}
}
