import SwiftData
import SwiftUI

struct SceneBar: View {
	@Environment(Console.self) private var console
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	
	let transition: Namespace.ID
	
	var body: some View {
		let shown = console.shownScene(among: looks.map(\.identifier).filter(console.playback.order.contains))
		
		Group {
			if let look = looks.first(where: { $0.identifier == shown }), let list = console.lists[look.identifier] {
				let index = list.index(of: console.playback.cue(of: look.identifier))
				let tint = look.tint.color
				let canGoBack = index.flatMap(list.previous(before:)) != nil
				let isAtEnd = console.upcoming(list) == nil
				
				HStack(spacing: 4) {
					Button {
						console.selection.open(scene: look.identifier, isSheet: true)
					} label: {
						HStack(spacing: 8) {
							Image(systemName: look.symbol)
								.font(.caption)
								.foregroundStyle(.white)
								.frame(width: 26, height: 26)
								.background(tint, in: .circle)
							
							VStack(alignment: .leading, spacing: 0) {
								Text(look.name)
									.font(.subheadline.weight(.medium))
								
								CueStatus(fade: console.playback.fade(of: look.identifier), follow: index.flatMap { list.cues[$0].follow }) {
									if !list.status(at: index).isEmpty {
										Text(list.status(at: index))
									}
								}
								.font(.caption)
								.foregroundStyle(.secondary)
							}
							.lineLimit(1)
							
							Spacer(minLength: 0)
						}
						.contentShape(.rect)
					}
					.buttonStyle(.plain)
					.matchedTransitionSource(id: "scene", in: transition)
					.accessibilityHint("Shows its cues.")
					
					Group {
						if list.cues.count > 1 {
							Button("Back", systemImage: SceneAction.back.symbol) {
								console.back(list)
							}
							.foregroundStyle(canGoBack ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
							.disabled(!canGoBack)
							
							Button("Next Cue", systemImage: SceneAction.next.symbol) {
								console.go(list)
							}
							.foregroundStyle(isAtEnd ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
							.disabled(isAtEnd)
						}
						
						Button("Turn Off", systemImage: "stop.fill") {
							console.toggle(list)
						}
					}
					.labelStyle(.iconOnly)
					.font(.title3)
					.frame(width: 44, height: 40)
					.contentShape(.rect)
				}
				.buttonStyle(.plain)
				.padding(.horizontal, 12)
			} else {
				MasterBar()
			}
		}
	}
}
