import SwiftUI

struct CueTimeline: View {
	let delay: Double
	let fade: Double
	let follow: Double?
	
	var height: CGFloat = 9
	
	var body: some View {
		ViewThatFits(in: .horizontal) {
			Segments(delay: delay, fade: fade, follow: follow, height: height, isStretched: true)
			
			Segments(delay: delay, fade: fade, follow: follow, height: height, isStretched: false)
			
			VStack(alignment: .trailing, spacing: 2) {
				if delay > 0 {
					Label(CueList.seconds(delay), systemImage: CueTime.delay.symbol)
				}
				
				Label(CueList.seconds(fade), systemImage: CueTime.fade.symbol)
				
				if let follow {
					Label(CueList.seconds(follow), systemImage: CueTime.follow.symbol)
				}
			}
			.labelStyle(.titleAndIcon)
			.monospacedDigit()
			.lineLimit(1)
			.fixedSize()
		}
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(CueList.timing(delay: delay, fade: fade, follow: follow))
	}
}

private struct Segments: View {
	let delay: Double
	let fade: Double
	let follow: Double?
	let height: CGFloat
	let isStretched: Bool
	
	var body: some View {
		let waiting = height * (isStretched ? CueList.span(of: delay) : CueList.span(of: 0))
		let fading = height * (isStretched ? CueList.span(of: fade) : CueList.span(of: 0))
		
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
	}
}
