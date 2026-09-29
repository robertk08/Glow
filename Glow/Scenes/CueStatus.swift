import SwiftUI

struct CueStatus<Rest: View>: View {
	let fade: Fade?
	let follow: Double?
	
	@ViewBuilder let rest: Rest
	
	var body: some View {
		TimelineView(.explicit([.now] + (fade?.moments(follow: follow) ?? []))) { context in
			switch fade?.phase(at: context.date, follow: follow) {
			case let .waiting(until) where until.timeIntervalSince(context.date) >= 1.5: Label { Text(timerInterval: context.date...until) } icon: { Image(systemName: CueTime.delay.symbol) }
			case let .following(until) where until.timeIntervalSince(context.date) >= 1.5: Label { Text(timerInterval: context.date...until) } icon: { Image(systemName: CueTime.follow.symbol) }
			default: rest
			}
		}
		.monospacedDigit()
	}
}
