import SwiftUI

struct CueStatus<Rest: View>: View {
	let fade: Fade?
	let follow: Double?
	
	@ViewBuilder let rest: Rest
	
	var body: some View {
		TimelineView(.explicit([.now] + (fade?.moments(follow: follow) ?? []))) { context in
			switch fade?.phase(at: context.date, follow: follow) {
			case let .waiting(until) where until.timeIntervalSince(context.date) >= 1.5: Text("Wait \(Text(timerInterval: context.date...until))")
			case let .following(until) where until.timeIntervalSince(context.date) >= 1.5: Text("Next in \(Text(timerInterval: context.date...until))")
			default: rest
			}
		}
		.monospacedDigit()
	}
}
