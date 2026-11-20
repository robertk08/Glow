import SwiftUI

struct DemoButton: ToolbarContent {
	@Environment(ShowLibrary.self) private var shows
	
	var body: some ToolbarContent {
		if shows.isDemo {
			ToolbarItem(placement: .topBarLeading) {
				Menu("Demo") {
					Button("Leave the Demo", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
						shows.stopDemo()
					}
				}
			}
		}
	}
}
