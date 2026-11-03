import SwiftUI

struct SceneFace: View {
	@Environment(Console.self) private var console
	@ScaledMetric(relativeTo: .headline) private var controls = 44
	
	let look: Look
	let list: CueList
	
	
	var body: some View {
		if !look.isGone {
			content
		}
	}
	
	@ViewBuilder private var content: some View {
		let index = list.index(of: console.playback.cue(of: look.identifier))
		let isOn = index != nil
		let size = look.size
		let isLarge = size == .large
		let tint = look.tint.color ?? .accentColor
		let fade = console.playback.fades[look.identifier]
		let upcoming = console.upcoming(list)
		let hasButtons = size != .small && !look.buttons.isEmpty
		let isInline = size == .wide && hasButtons
		let header = isInline ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
		
		VStack(alignment: .leading, spacing: 8) {
			header {
				Image(systemName: look.symbol)
					.font(.title3)
					.foregroundStyle(isOn ? Color.white : tint)
					.frame(width: 38, height: 38)
					.background(isOn ? tint : tint.opacity(0.16), in: .circle)
					.symbolEffect(.bounce, value: index)
				
				VStack(alignment: .leading, spacing: 2) {
					Text(look.name)
						.font(.headline)
						.lineLimit(1)
					
					if isLarge, list.cues.count > 1 {
						ViewThatFits(in: .vertical) {
							CueWindow(list: list, index: index, upcoming: upcoming, fade: fade, lines: 3)
							
							CueWindow(list: list, index: index, upcoming: upcoming, fade: fade, lines: 2)
							
							CueWindow(list: list, index: index, upcoming: upcoming, fade: fade, lines: 1)
						}
					} else if !isInline || look.tap == .flash || !list.status(at: index).isEmpty || console.isMoving(look.identifier) {
						CueStatus(fade: fade, follow: index.flatMap { list.cues[$0].follow }) {
							HStack(spacing: 4) {
								if look.tap == .flash {
									Image(systemName: SceneAction.flash.symbol)
								}
								
								Text(list.status(at: index).isEmpty ? " " : list.status(at: index))
									.contentTransition(.numericText())
							}
						}
						.font(.subheadline)
						.foregroundStyle(.secondary)
						.lineLimit(1)
						.animation(.snappy(duration: 0.3), value: index)
					}
				}
				.padding(.trailing, isInline ? 44 : 0)
			}
			.frame(maxHeight: .infinity, alignment: .topLeading)
			
			if list.cues.count > 1 {
				CueProgress(list: list, index: index, fade: fade, tint: tint)
					.padding(.vertical, isInline ? 0 : 6)
			}
			
			if hasButtons {
				Color.clear
					.frame(height: controls)
			}
		}
		.foregroundStyle(.primary)
		.padding(14)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		.background {
			if list.cues.count == 1 {
				Rectangle()
					.fill(tint.opacity(0.22))
					.scaleEffect(x: 1, y: isOn ? 1 : 0, anchor: .bottom)
					.animation(isOn ? fade?.rise ?? .snappy(duration: 0.25) : Fade.fall(over: console.playback.falls[look.identifier] ?? 0), value: isOn)
					.clipShape(.rect(cornerRadius: 24, style: .continuous))
			}
		}
		.glassEffect(.regular.tint(isOn && list.cues.count > 1 ? tint.opacity(0.22) : nil), in: .rect(cornerRadius: 24, style: .continuous))
		.contentShape(.rect(cornerRadius: 24, style: .continuous))
		.animation(.snappy(duration: 0.25), value: isOn)
	}
}

private struct CueWindow: View {
	let list: CueList
	let index: Int?
	let upcoming: Int?
	let fade: Fade?
	let lines: Int
	
	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			ForEach(Array(list.window(live: index, upcoming: upcoming).prefix(lines).enumerated()), id: \.offset) { slot, position in
				HStack(spacing: 6) {
					if position == upcoming {
						Image(systemName: SceneAction.next.symbol)
							.font(.caption)
							.transition(.scale.combined(with: .opacity))
					}
					
					if position == index {
						CueStatus(fade: fade, follow: list.cues[position].follow) {
							Text(list.heading(at: position))
								.contentTransition(.numericText())
						}
					} else {
						Text(list.heading(at: position))
							.contentTransition(.numericText())
					}
				}
				.font(slot == 0 && index != nil ? .title3.weight(.semibold) : .subheadline)
				.foregroundStyle(slot == 0 ? AnyShapeStyle(.primary) : slot == 1 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
				.lineLimit(1)
				.transition(.opacity)
			}
		}
		.padding(.top, 8)
		.animation(.snappy(duration: 0.3), value: [index ?? -1, upcoming ?? -1])
	}
}

private struct CueProgress: View {
	let list: CueList
	let index: Int?
	let fade: Fade?
	let tint: Color
	
	@State private var width = CGFloat.infinity
	
	var body: some View {
		Group {
			if CGFloat(list.cues.count) * 9 - 3 > width {
				ProgressView(value: Double(index.map { $0 + 1 } ?? 0), total: Double(list.cues.count))
			} else {
				HStack(spacing: 3) {
					ForEach(list.cues.indices, id: \.self) { position in
						if position == index {
							FadeBar(fade: fade, tint: tint)
						} else {
							ProgressView(value: index.map { position < $0 } == true ? 1 : 0)
						}
					}
				}
			}
		}
		.progressViewStyle(.linear)
		.tint(tint)
		.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
		.accessibilityHidden(true)
	}
}
