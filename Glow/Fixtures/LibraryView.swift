import SwiftData
import SwiftUI

struct LibraryView: View {
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.modelContext) private var context
	@Environment(\.dismiss) private var dismiss
	@Query private var stored: [StoredFixtureType]
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	var patching: Binding<Bool>?
	
	@State private var query = ""
	@State private var isBuilding = false
	@State private var deleting: StoredFixtureType?
	
	var body: some View {
		let results = library.search(query)
		let made = results.filter { type in library.made.contains { $0.id == type.id } }
		let builtIn = results.filter { type in library.builtIn.contains { $0.id == type.id } }
		
		return List {
			Section {
				Button("Build a Fixture", systemImage: "slider.horizontal.3") {
					isBuilding = true
				}
			} footer: {
				Text("Anything with a DMX address can go here, whether or not Glow ships a definition for it.")
			}
			
			if !made.isEmpty {
				Section("Made Here") {
					ForEach(made) { type in
						NavigationLink {
							FixtureTypeView(type: type, patching: patching)
						} label: {
							FixtureTypeRow(type: type)
						}
						.swipeActions {
							Button("Delete", systemImage: "trash", role: .destructive) {
								deleting = stored.first { $0.identifier == type.id }
							}
						}
					}
				}
			}
			
			Section(made.isEmpty ? "" : "Built In") {
				ForEach(builtIn) { type in
					NavigationLink {
						FixtureTypeView(type: type, patching: patching)
					} label: {
						FixtureTypeRow(type: type)
					}
				}
			}
		}
		.navigationTitle(patching == nil ? "Fixtures" : "Add Light")
		.searchable(text: $query)
		.overlay {
			if results.isEmpty {
				ContentUnavailableView {
					Label("Nothing Found", systemImage: "magnifyingglass")
				} description: {
					Text("Try a different name, or build the fixture yourself.")
				} actions: {
					Button("Build a Fixture", systemImage: "slider.horizontal.3") {
						isBuilding = true
					}
					.font(.headline)
					.buttonStyle(.glassProminent)
					.controlSize(.large)
				}
			}
		}
		.toolbar {
			if patching != nil {
				ToolbarItem(placement: .cancellationAction) {
					Button(role: .close) { dismiss() }
				}
			}
		}
		.sheet(isPresented: $isBuilding) {
			FixtureTypeEditor()
		}
		.confirmationDialog("Delete \(deleting?.definition.model ?? "")?", isPresented: Binding { deleting != nil } set: { _ in deleting = nil }, titleVisibility: .visible) {
			Button("Delete Fixture", role: .destructive) {
				if let deleting {
					context.delete(deleting)
				}
				deleting = nil
			}
		} message: {
			Text(library.patched(deleting?.identifier, among: fixtures).isEmpty ? "Nothing is patched from it." : "\(library.patched(deleting?.identifier, among: fixtures).formatted(.list(type: .and))) are patched from it and go with it.")
		}
	}
}
