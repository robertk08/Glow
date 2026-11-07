import SwiftUI

struct TileControls: View {
	@Environment(Console.self) private var console
	@Environment(\.horizontalSizeClass) private var sizeClass
	
	let look: Look
	let list: CueList
	
	var isShown = false
	
	var body: some View {
		VStack(spacing: 0) {
			HStack {
				Spacer(minLength: 0)
				
				if list.cues.count > 1 || isShown {
					Button("Show Cues", systemImage: "list.bullet") {
						console.selection.scene = look.identifier
						console.selection.isSceneOpen = sizeClass != .regular
					}
					.labelStyle(.iconOnly)
					.font(.body.weight(.semibold))
					.foregroundStyle(isShown ? AnyShapeStyle(look.tint.color) : AnyShapeStyle(.secondary))
					.frame(width: 44, height: 44)
					.contentShape(.rect)
					.hoverEffect(.highlight)
					.buttonStyle(.plain)
					.accessibilityAddTraits(isShown ? .isSelected : [])
					.transition(.scale.combined(with: .opacity))
				}
			}
			.animation(.snappy(duration: 0.25), value: isShown)
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
