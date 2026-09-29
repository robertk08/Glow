import SwiftUI

struct FadeBar: View {
	let fade: Fade?
	let tint: Color
	
	var body: some View {
		TimelineView(.explicit([.now] + (fade?.moments(follow: nil) ?? []))) { context in
			switch fade?.phase(at: context.date, follow: nil) {
			case .waiting: ProgressView(value: 0)
			case let .fading(span): ProgressView(timerInterval: span, countsDown: false) {} currentValueLabel: {}
			default: ProgressView(value: 1)
			}
		}
		.progressViewStyle(.linear)
		.tint(tint)
		.accessibilityHidden(true)
	}
}
