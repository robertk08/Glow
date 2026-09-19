import SwiftUI

struct ColorPad: View {
	@Binding var light: LightColor
	
	let isActive: Bool
	
	@State private var isDragging = false
	
	private let wheel = AngularGradient(colors: [
		Color(hue: 0, saturation: 1, brightness: 1),
		Color(hue: 0.167, saturation: 1, brightness: 1),
		Color(hue: 0.333, saturation: 1, brightness: 1),
		Color(hue: 0.5, saturation: 1, brightness: 1),
		Color(hue: 0.667, saturation: 1, brightness: 1),
		Color(hue: 0.833, saturation: 1, brightness: 1),
		Color(hue: 1, saturation: 1, brightness: 1),
	], center: .center)
	
	var body: some View {
		GeometryReader { proxy in
			let side = min(proxy.size.width, proxy.size.height)
			let radius = side / 2 - 24
			let centre = CGPoint(x: proxy.size.width / 2, y: side / 2)
			let angle = light.hue * 2 * .pi - .pi / 2
			let knob = CGPoint(x: centre.x + cos(angle) * radius * light.saturation, y: centre.y + sin(angle) * radius * light.saturation)
			
			ZStack {
				Circle()
					.fill(wheel)
					.rotationEffect(.degrees(-90))
					.overlay {
						Circle()
							.fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 0, endRadius: radius))
					}
					.overlay {
						Circle()
							.strokeBorder(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator), lineWidth: isActive ? 2 : 1)
					}
					.frame(width: radius * 2, height: radius * 2)
					.contentShape(.circle)
					.gesture(
						DragGesture(minimumDistance: 0)
							.onChanged { drag in
								isDragging = true
								let dx = drag.location.x - radius
								let dy = drag.location.y - radius
								let reach = min((dx * dx + dy * dy).squareRoot() / radius, 1)
								let turn = (atan2(dy, dx) + .pi / 2) / (2 * .pi)
								light = LightColor(hue: turn - turn.rounded(.down), saturation: reach)
							}
							.onEnded { _ in isDragging = false }
					)
					.position(centre)
				
				Circle()
					.fill(light.color)
					.frame(width: isDragging ? 44 : 32)
					.overlay {
						Circle()
							.strokeBorder(.white, lineWidth: 3)
					}
					.shadow(radius: 3, y: 1)
					.position(knob)
					.animation(.snappy(duration: 0.15), value: isDragging)
			}
		}
		.frame(height: 232)
		.accessibilityElement()
		.accessibilityLabel("Color")
		.sensoryFeedback(.selection, trigger: isDragging)
	}
}
