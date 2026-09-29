import SwiftUI

struct CueStatus: View {
	let text: String
	let fade: Fade?
	let follow: Double?
	
	var body: some View {
		TimelineView(.explicit([.now] + (fade?.moments(follow: follow) ?? []))) { context in
			switch fade?.phase(at: context.date, follow: follow) {
			case let .waiting(until): Text("Waits \(Text(timerInterval: context.date...until))")
			case let .following(until): Text("Next in \(Text(timerInterval: context.date...until))")
			default: Text(text)
			}
		}
		.monospacedDigit()
	}
}
