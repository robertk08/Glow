import SwiftUI

struct TileButtons: View {
	@Environment(Console.self) private var console
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
		let isLarge = look.size == .large
		let tint = look.tint.color ?? .accentColor
		let shown = look.buttons(live: index, upcoming: upcoming, count: list.cues.count)
		
		GlassEffectContainer(spacing: isLarge ? 10 : 6) {
			HStack(spacing: isLarge ? 10 : 6) {
				ForEach(shown) { action in
					let isProminent = action == .next && index != nil
					
					Button {
						if action != .flash {
							console.run(action, on: list)
						}
					} label: {
						Label(action.name(isOn: index != nil), systemImage: action.symbol(isOn: index != nil))
							.labelStyle(.iconOnly)
							.font(.body.weight(.semibold))
							.foregroundStyle(isProminent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
							.contentTransition(.symbolEffect(.replace))
							.frame(minWidth: 48, maxWidth: isLarge ? .infinity : 48, minHeight: isLarge ? height : 40)
							.glassEffect(.regular.tint(isProminent ? tint : nil).interactive(), in: .capsule)
							.contentShape(.capsule)
					}
					.buttonStyle(PressStyle(flashes: action == .flash) { isHeld in
						console.flash(list, isHeld: isHeld)
					})
					.transition(.scale(scale: 0.6).combined(with: .opacity))
				}
			}
		}
		.animation(.snappy(duration: 0.25), value: shown)
	}
}
