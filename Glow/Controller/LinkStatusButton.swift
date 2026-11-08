import SwiftUI

struct LinkStatusButton: ToolbarContent {
	@Environment(Console.self) private var console
	
	@State private var isShowing = false
	
	var body: some ToolbarContent {
		ToolbarItem(placement: .topBarLeading) {
			Button("Controller", systemImage: console.link.isConnected ? "wifi" : "wifi.exclamationmark") {
				isShowing = true
			}
			.labelStyle(.iconOnly)
			.tint(console.link.isConnected ? Color.green : Color.orange)
			.popover(isPresented: $isShowing) {
				NavigationStack {
					NodeView()
						.toolbar {
							ToolbarItem(placement: .confirmationAction) {
								Button(role: .close) { isShowing = false }
							}
						}
				}
				.frame(idealWidth: 420, idealHeight: 620)
			}
			.onChange(of: console.selection.isSetupOpen) {
				guard console.selection.isSetupOpen, isShowing else { return }
				console.selection.isSetupOpen = false
				isShowing = false
				Task {
					try? await Task.sleep(for: .seconds(0.5))
					console.selection.isSetupOpen = true
				}
			}
		}
	}
}
