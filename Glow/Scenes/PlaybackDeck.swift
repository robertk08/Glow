import SwiftData
import SwiftUI

struct PlaybackDeck: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.modelContext) private var context
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	@Query(sort: \Cue.number) private var cues: [Cue]
	
	let look: Look
	
	var body: some View {
		let list = CueList(look, cues: cues, fixtures: fixtures, library: library)
		let index = list.index(of: console.activeCue)
		let next = list.upcoming(after: index)
		let current = cues.first { $0.identifier == console.activeCue }
		
		VStack(spacing: 12) {
			HStack(alignment: .top, spacing: 12) {
				VStack(alignment: .leading, spacing: 2) {
					Text(index.map { "\(look.name) · Cue \(list.cues[$0].numberText)" } ?? look.name)
						.font(.caption.weight(.semibold))
						.foregroundStyle(.secondary)
						.lineLimit(1)
					
					Text(index.map { list.cues[$0].title } ?? "Ready")
						.font(.headline)
						.lineLimit(1)
						.contentTransition(.numericText())
				}
				
				Spacer(minLength: 8)
				
				if let next {
					VStack(alignment: .trailing, spacing: 2) {
						Label("Next", systemImage: list.cues[next].trigger.symbol)
							.font(.caption.weight(.semibold))
							.foregroundStyle(.secondary)
						
						Text(list.cues[next].title)
							.font(.subheadline)
							.lineLimit(1)
					}
				}
			}
			
			if let index {
				CueProgress(cue: list.cues[index])
			}
			
			HStack(spacing: 10) {
				Button("Back", systemImage: "backward.end.fill") {
					console.back(list)
				}
				.labelStyle(.iconOnly)
				.buttonStyle(.glass)
				.controlSize(.large)
				.disabled(index.flatMap(list.previous(before:)) == nil)
				
				Button {
					console.go(list)
				} label: {
					Label("Go", systemImage: "play.fill")
						.font(.headline)
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.glassProminent)
				.controlSize(.large)
				.keyboardShortcut(.space, modifiers: [])
				.disabled(next == nil)
				
				if console.isRunning {
					Button("Stop", systemImage: "stop.fill") {
						console.stop()
					}
					.labelStyle(.iconOnly)
					.buttonStyle(.glass)
					.controlSize(.large)
				} else if let current, !console.active.isEmpty {
					Button("Update Cue", systemImage: "square.and.arrow.down") {
						Recording(.into(current), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues).store(context: context)
					}
					.labelStyle(.iconOnly)
					.buttonStyle(.glass)
					.controlSize(.large)
				}
			}
		}
		.padding(16)
		.glassEffect(.regular, in: .rect(cornerRadius: 28, style: .continuous))
		.frame(maxWidth: 560)
		.padding(.horizontal)
		.padding(.bottom, 8)
		.animation(.snappy, value: console.activeCue)
		.sensoryFeedback(.impact(weight: .medium), trigger: console.activeCue)
	}
}
