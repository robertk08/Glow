import SwiftData
import SwiftUI

struct RootView: View {
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.horizontalSizeClass) private var sizeClass
	@Query private var customProfiles: [CustomProfile]
	
	var body: some View {
		Group {
			if sizeClass == .regular {
				LightsView()
			} else {
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
			}
		}
		.onChange(of: customProfiles) {
			library.setCustom(customProfiles.map(\.profile))
		}
		.task {
			library.setCustom(customProfiles.map(\.profile))
		}
	}
}
