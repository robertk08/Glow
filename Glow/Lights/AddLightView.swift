import SwiftUI

struct AddLightView: View {
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.dismiss) private var dismiss
	
	@Binding var isPresented: Bool
	
	@State private var query = ""
	@State private var isBuilding = false
	
	private var results: [FixtureProfile] { library.search(query) }
	
	var body: some View {
		NavigationStack {
			List {
				Section {
					Button("Build a Fixture", systemImage: "slider.horizontal.3") {
						isBuilding = true
					}
				} footer: {
					Text("Anything with a DMX address can go here, whether or not Glow ships a profile for it.")
				}
				
				Section {
					ForEach(results) { profile in
						NavigationLink {
							PatchView(profile: profile, isPresented: $isPresented)
						} label: {
							ProfileRow(profile: profile)
						}
					}
				}
			}
			.navigationTitle("Add Light")
			.navigationBarTitleDisplayMode(.inline)
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
				Button(role: .close) { dismiss() }
			}
			.sheet(isPresented: $isBuilding) {
				CustomFixtureView()
			}
		}
	}
}
