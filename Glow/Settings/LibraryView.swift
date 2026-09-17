import SwiftData
import SwiftUI

struct LibraryView: View {
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.modelContext) private var context
	@Query(sort: \CustomProfile.createdAt) private var customProfiles: [CustomProfile]
	
	@State private var query = ""
	
	private var results: [FixtureProfile] { library.search(query) }
	
	private var built: [CustomProfile] {
		customProfiles.filter { profile in results.contains { $0.id == profile.identifier } }
	}
	
	var body: some View {
		List {
			if !built.isEmpty {
				Section("Built Here") {
					ForEach(built) { custom in
						NavigationLink {
							ProfileView(profile: custom.profile)
						} label: {
							Label(custom.name, systemImage: custom.symbol)
						}
					}
					.onDelete { offsets in
						for index in offsets {
							context.delete(customProfiles[index])
						}
					}
				}
			}
			
			Section {
				ForEach(results.filter { profile in !customProfiles.contains { $0.identifier == profile.id } }) { profile in
					NavigationLink {
						ProfileView(profile: profile)
					} label: {
						ProfileRow(profile: profile)
					}
				}
			}
		}
		.navigationTitle("Fixtures")
		.searchable(text: $query)
	}
}
