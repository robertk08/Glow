import SwiftData
import SwiftUI

struct RootView: View {
	@Environment(FixtureLibrary.self) private var library
	@Query private var customProfiles: [CustomProfile]
	
	var body: some View {
		TabView {
			Tab("Lights", systemImage: "lightbulb") {
				LightsView()
			}
			
			Tab("Scenes", systemImage: "theatermasks") {
				ScenesView()
			}
		}
		.tabViewBottomAccessory {
			MasterBar()
		}
		.onChange(of: customProfiles) {
			library.setCustom(customProfiles.map(\.profile))
		}
		.task {
			library.setCustom(customProfiles.map(\.profile))
		}
	}
}
