import SwiftUI

struct TileControls: View {
	@Environment(Console.self) private var console
	@Environment(\.horizontalSizeClass) private var sizeClass
	
	let look: Look
	let list: CueList
	
	var isEditing = false
	
	var body: some View {
		VStack(spacing: 0) {
			HStack {
				Spacer(minLength: 0)
				
				if isEditing {
					Image(systemName: "slider.horizontal.3")
						.font(.body.weight(.semibold))
						.foregroundStyle(.secondary)
						.frame(width: 44, height: 44)
						.allowsHitTesting(false)
						.transition(.scale.combined(with: .opacity))
				} else if list.cues.count > 1, look.size == .small || !look.buttons.contains(.open) {
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
			
			if look.size != .small, !look.buttons.isEmpty, !isEditing {
				TileButtons(look: look, list: list)
					.padding(14)
					.transition(.opacity)
			}
		}
	}
}
