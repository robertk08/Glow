import SwiftData
import SwiftUI

struct SceneBar: View {
	@Environment(Console.self) private var console
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	@Query(sort: \Cue.sortIndex) private var cues: [Cue]
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	let transition: Namespace.ID
	
	var body: some View {
		let lists = CueList.all(looks, cues: cues, fixtures: fixtures)
		let playing = console.playback.playing.map(\.scene)
		let shown = console.shownScene(among: lists.map(\.scene).filter(playing.contains))
		
		Group {
			if let look = looks.first(where: { $0.identifier == shown }), let list = lists.first(where: { $0.scene == shown }) {
				let index = list.index(of: console.playback.cue(of: look.identifier))
				let tint = look.tint.color ?? .accentColor
				
				HStack(spacing: 4) {
					Button {
						console.selection.scene = look.identifier
						console.selection.isSceneOpen = true
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
								
								CueStatus(fade: console.playback.fades[look.identifier], follow: index.flatMap { list.cues[$0].follow }) {
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
							
							Button("Next Cue", systemImage: SceneAction.next.symbol) {
								console.go(list)
							}
							.disabled(console.upcoming(list) == nil)
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
