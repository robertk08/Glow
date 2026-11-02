import SwiftUI

struct SceneFace: View {
	@Environment(Console.self) private var console
	@ScaledMetric(relativeTo: .headline) private var controls = 44
	
	let look: Look
	let list: CueList
	
	var showsButtons = false
	
	var body: some View {
		if !look.isGone {
			content
		}
	}
	
	@ViewBuilder private var content: some View {
		let index = list.index(of: console.playback.cue(of: look.identifier))
		let isOn = index != nil
		let isLarge = look.size == .large
		let tint = look.tint.color ?? .accentColor
		let fade = console.playback.fades[look.identifier]
		let upcoming = console.upcoming(list)
		
		VStack(alignment: .leading, spacing: 8) {
			HStack(alignment: .top) {
				Image(systemName: look.symbol)
					.font(.title3)
					.foregroundStyle(isOn ? Color.white : tint)
					.frame(width: 38, height: 38)
					.background(isOn ? tint : tint.opacity(0.16), in: .circle)
					.symbolEffect(.bounce, value: index)
				
				Spacer(minLength: 0)
				
				if showsButtons, look.size == .wide {
					TileButtons(look: look, list: list)
				}
			}
			
			VStack(alignment: .leading, spacing: 2) {
				Text(look.name)
					.font(.headline)
					.lineLimit(1)
				
				if isLarge, list.cues.count > 1 {
					VStack(alignment: .leading, spacing: 6) {
						ForEach(list.window(live: index, upcoming: upcoming), id: \.self) { position in
							HStack(spacing: 6) {
								if position == upcoming {
									Image(systemName: SceneAction.next.symbol)
										.font(.caption)
								}
								
								if position == index {
									CueStatus(fade: fade, follow: list.cues[position].follow) {
										Text(list.heading(at: position))
									}
								} else {
									Text(list.heading(at: position))
								}
							}
							.font(position == index ? .title3.weight(.semibold) : .subheadline)
							.foregroundStyle(position == index ? AnyShapeStyle(.primary) : position == upcoming ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
							.lineLimit(1)
							.transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity.animation(.easeOut(duration: 0.12))))
						}
					}
					.padding(.top, 8)
					.animation(.snappy, value: [index ?? -1, upcoming ?? -1])
				} else {
					CueStatus(fade: fade, follow: index.flatMap { list.cues[$0].follow }) {
						HStack(spacing: 4) {
							if look.tap == .flash {
								Image(systemName: SceneAction.flash.symbol)
							}
							
							Text(list.status(at: index).isEmpty ? " " : list.status(at: index))
						}
					}
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.lineLimit(1)
				}
			}
			
			if isLarge {
				Spacer(minLength: 0)
			}
			
			CueProgress(list: list, index: index, fade: fade, tint: tint)
				.padding(.vertical, 6)
			
			if isLarge {
				Group {
					if showsButtons {
						TileButtons(look: look, list: list)
					} else {
						Color.clear
					}
				}
				.frame(height: controls)
			}
		}
		.foregroundStyle(.primary)
		.padding(14)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		.glassEffect(.regular.tint(isOn ? tint.opacity(0.22) : nil), in: .rect(cornerRadius: 24, style: .continuous))
		.contentShape(.rect(cornerRadius: 24, style: .continuous))
		.animation(.snappy, value: isOn)
	}
}

private struct CueProgress: View {
	let list: CueList
	let index: Int?
	let fade: Fade?
	let tint: Color
	
	var body: some View {
		Group {
			if list.isLong {
				ProgressView(value: Double(index.map { $0 + 1 } ?? 0), total: Double(list.cues.count))
			} else if list.cues.count > 1 {
				HStack(spacing: 3) {
					ForEach(list.cues.indices, id: \.self) { position in
						if position == index {
							FadeBar(fade: fade, tint: tint)
						} else {
							ProgressView(value: index.map { position < $0 } == true ? 1 : 0)
						}
					}
				}
			} else {
				FadeBar(fade: fade, tint: tint)
					.opacity(index == nil ? 0 : 1)
			}
		}
		.progressViewStyle(.linear)
		.tint(tint)
		.accessibilityHidden(true)
	}
}
