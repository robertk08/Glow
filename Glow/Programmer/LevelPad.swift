import SwiftUI

struct LevelPad: View {
	@Binding var level: Double
	
	let glow: Color
	let isActive: Bool
	
	@State private var isDragging = false
	@State private var origin: Double?
	
	var body: some View {
		GeometryReader { proxy in
			let width = proxy.size.width
			
			ZStack(alignment: .leading) {
				Rectangle()
					.fill(.fill.quaternary)
				
				Rectangle()
					.fill(glow.gradient)
					.frame(width: max(0, width * level))
				
				HStack {
					Text(level, format: .percent.precision(.fractionLength(0)))
						.font(.system(size: 30, weight: .semibold).monospacedDigit())
						.contentTransition(.numericText(value: level))
						.foregroundStyle(level > 0.3 ? LightColor(glow).contrastingInk : Color.primary)
					
					Spacer()
				}
				.padding(.horizontal, 18)
			}
			.contentShape(.rect)
			.gesture(
				DragGesture(minimumDistance: 0)
					.onChanged { drag in
						if origin == nil {
							origin = level
							isDragging = true
						}
						level = min(max((origin ?? 0) + drag.translation.width / width, 0), 1)
					}
					.onEnded { _ in
						origin = nil
						isDragging = false
					}
			)
		}
		.frame(height: 92)
		.clipShape(.rect(cornerRadius: 20, style: .continuous))
		.overlay {
			RoundedRectangle(cornerRadius: 20, style: .continuous)
				.strokeBorder(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator), lineWidth: isActive ? 2 : 1)
		}
		.scaleEffect(isDragging ? 1.02 : 1)
		.animation(.snappy(duration: 0.2), value: isDragging)
		.accessibilityElement()
		.accessibilityLabel("Intensity")
		.accessibilityValue(level.formatted(.percent.precision(.fractionLength(0))))
		.accessibilityAdjustableAction { direction in
			level = min(max(level + (direction == .increment ? 0.05 : -0.05), 0), 1)
		}
		.sensoryFeedback(.selection, trigger: isDragging)
	}
}
