import SwiftData
import SwiftUI

struct LibraryView: View {
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.dismiss) private var dismiss
	
	var patching: Binding<Bool>?
	
	@State private var query = ""
	@State private var isBuilding = false
	
	var body: some View {
		let results = library.search(query)
		let made = results.filter { type in library.made.contains { $0.id == type.id } }
		let builtIn = results.filter { type in library.builtIn.contains { $0.id == type.id } }
		
		return List {
			Section {
				Button("Create Fixture", systemImage: "slider.horizontal.3") {
					isBuilding = true
				}
			}
			
			if !made.isEmpty {
				Section("Made Here") {
					ForEach(made) { type in
						MadeFixtureRow(type: type, patching: patching)
					}
				}
			}
			
			Section {
				ForEach(builtIn) { type in
					NavigationLink {
						FixtureTypeView(type: type, patching: patching)
					} label: {
						FixtureTypeRow(type: type)
					}
				}
			} header: {
				if !made.isEmpty {
					Text("Built In")
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
					Text("Try a different name, or create the fixture yourself.")
				} actions: {
					Button("Create Fixture", systemImage: "slider.horizontal.3") {
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
	}
}

private struct MadeFixtureRow: View {
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.modelContext) private var context
	@Query private var stored: [StoredFixtureType]
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	let type: FixtureType
	
	var patching: Binding<Bool>?
	
	@State private var isDeleting = false
	
	var body: some View {
		let patched = library.patched(type.id, among: fixtures)
		
		NavigationLink {
			FixtureTypeView(type: type, patching: patching)
		} label: {
			FixtureTypeRow(type: type)
		}
		.swipeActions(edge: .trailing, allowsFullSwipe: false) {
			Button("Delete", systemImage: "trash") {
				isDeleting = true
			}
			.tint(.red)
		}
		.alert("Delete \(type.model)?", isPresented: $isDeleting) {
			Button("Cancel", role: .cancel) {}
			
			Button("Delete", role: .destructive) {
				guard let found = stored.first(where: { $0.identifier == type.id }) else { return }
				context.delete(found)
			}
		} message: {
			Text(patched.isEmpty ? "Nothing is patched from it." : "Lights patched from it stay and will need another fixture: \(patched.formatted(.list(type: .and))).")
		}
	}
}
