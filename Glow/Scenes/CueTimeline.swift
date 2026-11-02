import SwiftUI

struct CueTimeline: View {
	let delay: Double
	let fade: Double
	let follow: Double?
	
	var height: CGFloat = 9
	
	var body: some View {
		let waiting = height * CueList.span(of: delay)
		let fading = height * CueList.span(of: fade)
		
		HStack(alignment: .top, spacing: 4) {
			if delay > 0 {
				VStack(spacing: 3) {
					Path { path in
						path.move(to: CGPoint(x: 0, y: height))
						path.addLine(to: CGPoint(x: waiting, y: height))
					}
					.stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [1, 3.5]))
					.frame(width: waiting, height: height)
					
					Text(CueList.seconds(delay))
				}
			}
			
			VStack(spacing: 3) {
				Path { path in
					path.move(to: CGPoint(x: 0, y: height))
					path.addLine(to: CGPoint(x: fade > 0 ? fading * 0.75 : 0, y: 0))
					path.addLine(to: CGPoint(x: fading, y: 0))
				}
				.stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
				.frame(width: fading, height: height)
				
				Text(fade > 0 ? CueList.seconds(fade) : " ")
			}
			
			if let follow {
				VStack(spacing: 3) {
					Image(systemName: CueTime.follow.symbol)
						.font(.system(size: height + 2, weight: .semibold))
						.frame(height: height)
					
					Text(follow > 0 ? CueList.seconds(follow) : " ")
				}
			}
		}
		.monospacedDigit()
		.fixedSize()
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(CueList.timing(delay: delay, fade: fade, follow: follow))
	}
	
	static func width(of seconds: Double, height: CGFloat) -> CGFloat {
		height * (1.6 + 1.4 * log2(1 + min(seconds, 60)))
	}
}
