import SwiftData
import SwiftUI

struct ScenesView: View {
	var body: some View {
		NavigationStack {
			List {
				SceneSections()
			}
			.navigationTitle("Scenes")
			.toolbar {
				SettingsToolbarButton()
				
				ToolbarItem(placement: .topBarTrailing) {
					EditButton()
				}
			}
		}
	}
}
