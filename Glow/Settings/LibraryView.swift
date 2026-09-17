import SwiftData
import SwiftUI

struct LibraryView: View {
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.modelContext) private var context
	@Environment(\.dismiss) private var dismiss
	@Query(sort: \CustomProfile.createdAt) private var customProfiles: [CustomProfile]
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	var patching: Binding<Bool>?
	
	@State private var query = ""
	@State private var isBuilding = false
	@State private var deleting: CustomProfile?
	
	private var results: [FixtureProfile] { library.search(query) }
	
	private var built: [CustomProfile] {
		customProfiles.filter { profile in results.contains { $0.id == profile.identifier } }
	}
	
	private var bundled: [FixtureProfile] {
		results.filter { profile in !customProfiles.contains { $0.identifier == profile.id } }
	}
	
	var body: some View {
		List {
			Section {
				Button("Build a Fixture", systemImage: "slider.horizontal.3") {
					isBuilding = true
				}
			} footer: {
				Text("Anything with a DMX address can go here, whether or not Glow ships a profile for it.")
			}
			
			if !built.isEmpty {
				Section("Built Here") {
					ForEach(built) { custom in
						NavigationLink {
							if let patching {
								PatchView(profile: custom.profile, isPresented: patching)
							} else {
								ProfileView(profile: custom.profile)
							}
						} label: {
							ProfileRow(profile: custom.profile)
						}
						.swipeActions {
							Button("Delete", systemImage: "trash", role: .destructive) {
								deleting = custom
							}
						}
					}
				}
			}
			
			Section(built.isEmpty ? "" : "Built In") {
				ForEach(bundled) { profile in
					NavigationLink {
						if let patching {
							PatchView(profile: profile, isPresented: patching)
						} else {
							ProfileView(profile: profile)
						}
					} label: {
						ProfileRow(profile: profile)
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
			CustomFixtureView()
		}
		.confirmationDialog("Delete \(deleting?.name ?? "")?", isPresented: Binding { deleting != nil } set: { _ in deleting = nil }, titleVisibility: .visible) {
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
