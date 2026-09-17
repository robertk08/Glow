import SwiftUI

struct SettingsToolbarButton: ToolbarContent {
	@Environment(Console.self) private var console
	
	@State private var isShowing = false
	
	var body: some ToolbarContent {
		ToolbarItem(placement: .topBarLeading) {
			Button("Settings", systemImage: console.link.isConnected ? "gearshape" : "wifi.exclamationmark") {
				isShowing = true
			}
			.foregroundStyle(console.link.isConnected ? Color.accentColor : Color.orange)
			.accessibilityValue(console.link.summary(latency: console.latency))
			.popover(isPresented: $isShowing) {
				SettingsView()
					.frame(idealWidth: 450, idealHeight: 700)
			}
		}
	}
}
