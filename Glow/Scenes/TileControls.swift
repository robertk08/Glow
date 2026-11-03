import SwiftUI

struct TileControls: View {
	@Environment(Console.self) private var console
	@Environment(\.horizontalSizeClass) private var sizeClass
	
	let look: Look
	let list: CueList
	
	var body: some View {
		VStack(spacing: 0) {
			HStack {
				Spacer(minLength: 0)
				
				if list.cues.count > 1 {
					Button("Show Cues", systemImage: "list.bullet") {
						console.selection.scene = look.identifier
						console.selection.isSceneOpen = sizeClass != .regular
					}
					.labelStyle(.iconOnly)
					.font(.body.weight(.semibold))
					.foregroundStyle(.secondary)
					.frame(width: 44, height: 44)
					.contentShape(.rect)
					.buttonStyle(.plain)
					.transition(.scale.combined(with: .opacity))
				}
			}
			.padding(11)
			
			Spacer(minLength: 0)
			
			if look.size != .small, !look.buttons.isEmpty {
				TileButtons(look: look, list: list)
					.padding(14)
					.transition(.opacity)
			}
		}
	}
}
