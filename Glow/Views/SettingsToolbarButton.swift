import SwiftUI

struct SettingsToolbarButton: ToolbarContent {
	@State private var isShowing = false
	
	var body: some ToolbarContent {
		ToolbarItem(placement: .topBarLeading) {
			Button("Settings", systemImage: "gearshape") {
				isShowing = true
			}
			.popover(isPresented: $isShowing) {
				SettingsView()
					.frame(idealWidth: 450, idealHeight: 700)
			}
		}
	}
}
