import SwiftUI

struct TileButtons: View {
	@Environment(Console.self) private var console
	@Environment(\.horizontalSizeClass) private var sizeClass
	@ScaledMetric(relativeTo: .headline) private var height = 44
	
	let look: Look
	let list: CueList
	
	var body: some View {
		if !look.isGone {
			content
		}
	}
	
	@ViewBuilder private var content: some View {
		let index = list.index(of: console.playback.cue(of: look.identifier))
		let upcoming = console.upcoming(list)
		let tint = look.tint.color ?? .accentColor
		
		GlassEffectContainer(spacing: 10) {
			HStack(spacing: 10) {
				ForEach(look.buttons) { action in
					let isEnabled = Look.enables(action, live: index, upcoming: upcoming, count: list.cues.count, isFlashing: console.flashing.contains(list.scene))
					let isProminent = action == .next && index != nil && isEnabled
					let isWide = action == .next || !look.buttons.contains(.next)
					
					Button {
						if action == .open {
							console.selection.scene = look.identifier
							console.selection.isSceneOpen = sizeClass != .regular
						} else if action != .flash {
							console.run(action, on: list)
						}
					} label: {
						Label(action.name(isOn: index != nil), systemImage: action.symbol(isOn: index != nil))
							.labelStyle(.iconOnly)
							.font(.body.weight(.semibold))
							.foregroundStyle(isProminent ? AnyShapeStyle(.white) : isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
							.contentTransition(.symbolEffect(.replace))
							.frame(maxWidth: isWide ? .infinity : height, minHeight: height)
							.glassEffect(.regular.tint(isProminent ? tint : nil).interactive(isEnabled), in: .capsule)
							.contentShape(.capsule)
					}
					.buttonStyle(PressStyle(flashes: action == .flash) { isHeld in
						console.flash(list, isHeld: isHeld)
					})
					.disabled(!isEnabled)
				}
			}
		}
		.animation(.snappy(duration: 0.25), value: [index ?? -1, upcoming ?? -1])
	}
}
