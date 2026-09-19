import SwiftUI

struct BeamPad: View {
	@Binding var zoom: Double
	@Binding var focus: Double
	
	let glow: Color
	let degrees: Double?
	let hasFocus: Bool
	
	@State private var isDragging = false
	
	var body: some View {
		GeometryReader { proxy in
			let width = proxy.size.width
			let height = proxy.size.height
			let spread = width * (0.12 + zoom * 0.72)
			let softness = 2 + (1 - focus) * 26
			
			ZStack {
				RoundedRectangle(cornerRadius: 18, style: .continuous)
					.fill(.fill.quaternary)
				
				Path { path in
					path.move(to: CGPoint(x: width / 2 - 9, y: 10))
					path.addLine(to: CGPoint(x: width / 2 + 9, y: 10))
					path.addLine(to: CGPoint(x: width / 2 + spread / 2, y: height - 12))
					path.addLine(to: CGPoint(x: width / 2 - spread / 2, y: height - 12))
					path.closeSubpath()
				}
				.fill(LinearGradient(colors: [glow.opacity(0.85), glow.opacity(0.08)], startPoint: .top, endPoint: .bottom))
				.blur(radius: softness)
				
				Ellipse()
					.fill(glow.opacity(0.9))
					.frame(width: spread, height: max(10, spread * 0.16))
					.blur(radius: softness * 0.6)
					.position(x: width / 2, y: height - 12)
				
				VStack {
					Spacer()
					
					if let degrees {
						Text("\(degrees.formatted(.number.precision(.fractionLength(0))))°")
							.font(.caption.monospacedDigit())
							.foregroundStyle(.secondary)
							.padding(.bottom, 4)
					}
				}
			}
			.contentShape(.rect(cornerRadius: 18))
			.gesture(
				DragGesture(minimumDistance: 0)
					.onChanged { drag in
						isDragging = true
						zoom = min(max(drag.location.x / width, 0), 1)
						if hasFocus { focus = min(max(1 - drag.location.y / height, 0), 1) }
					}
					.onEnded { _ in isDragging = false }
			)
		}
		.frame(height: 190)
		.accessibilityElement()
		.accessibilityLabel(hasFocus ? "Zoom and focus" : "Zoom")
		.sensoryFeedback(.selection, trigger: isDragging)
	}
}
