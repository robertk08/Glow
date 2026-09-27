import SwiftUI

struct FadeBar: View {
	let fade: Fade?
	let tint: Color
	
	var body: some View {
		TimelineView(.animation(paused: fade == nil)) { context in
			GeometryReader { proxy in
				Capsule()
					.fill(Color(.tertiarySystemFill))
					.overlay(alignment: .leading) {
						Capsule()
							.fill(tint)
							.frame(width: proxy.size.width * (fade?.fraction(at: context.date) ?? 1))
					}
			}
		}
		.frame(height: 6)
		.accessibilityHidden(true)
	}
}
