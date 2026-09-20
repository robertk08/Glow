import SwiftUI

struct PositionPad: View {
	@Binding var pan: Double
	@Binding var tilt: Double
	
	var panDegrees: Double?
	var tiltDegrees: Double?
	var isActive = false
	
	@State private var isDragging = false
	@State private var isFine = false
	@State private var anchor: CGPoint?
	@State private var origin = CGPoint.zero
	
	var body: some View {
		GeometryReader { proxy in
			let size = proxy.size
			let position = CGPoint(x: pan * size.width, y: (1 - tilt) * size.height)
			
			ZStack {
				RoundedRectangle(cornerRadius: 18, style: .continuous)
					.fill(.fill.quaternary)
				
				Path { path in
					for step in 1..<4 {
						let x = size.width * Double(step) / 4
						let y = size.height * Double(step) / 4
						path.move(to: CGPoint(x: x, y: 0))
						path.addLine(to: CGPoint(x: x, y: size.height))
						path.move(to: CGPoint(x: 0, y: y))
						path.addLine(to: CGPoint(x: size.width, y: y))
					}
				}
				.stroke(.separator.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
				
				Path { path in
					path.move(to: CGPoint(x: position.x, y: 0))
					path.addLine(to: CGPoint(x: position.x, y: size.height))
					path.move(to: CGPoint(x: 0, y: position.y))
					path.addLine(to: CGPoint(x: size.width, y: position.y))
				}
				.stroke(.tint.opacity(isDragging ? 0.65 : 0.3), lineWidth: 1)
				
				Circle()
					.fill(.tint)
					.frame(width: isDragging ? 34 : 26)
					.overlay {
						Circle()
							.strokeBorder(.white.opacity(0.9), lineWidth: 2)
					}
					.position(position)
					.animation(.snappy(duration: 0.15), value: isDragging)
				
				VStack {
					HStack {
						if isFine {
							Label("Fine", systemImage: "scope")
								.font(.caption2.weight(.medium))
								.padding(.horizontal, 8)
								.padding(.vertical, 4)
								.glassEffect(.regular.tint(.accentColor))
						}
						
						Spacer()
					}
					
					Spacer()
					
					HStack {
						Text(panDegrees.map { "\((pan * $0 - $0 / 2).formatted(.number.precision(.fractionLength(0))))°" } ?? pan.formatted(.percent.precision(.fractionLength(0))))
						
						Spacer()
						
						Text(tiltDegrees.map { "\((tilt * $0 - $0 / 2).formatted(.number.precision(.fractionLength(0))))°" } ?? tilt.formatted(.percent.precision(.fractionLength(0))))
					}
					.font(.caption.monospacedDigit())
					.foregroundStyle(.secondary)
				}
				.padding(10)
			}
			.overlay {
				RoundedRectangle(cornerRadius: 18, style: .continuous)
					.strokeBorder(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 2)
			}
			.contentShape(.rect(cornerRadius: 18))
			.gesture(
				DragGesture(minimumDistance: 0)
					.onChanged { drag in
						if anchor != drag.startLocation {
							anchor = drag.startLocation
							origin = CGPoint(x: pan, y: tilt)
							isDragging = true
						}
						
						guard isFine else {
							pan = min(max(drag.location.x / size.width, 0), 1)
							tilt = min(max(1 - drag.location.y / size.height, 0), 1)
							return
						}
						
						pan = min(max(origin.x + drag.translation.width / size.width / 6, 0), 1)
						tilt = min(max(origin.y - drag.translation.height / size.height / 6, 0), 1)
					}
					.onEnded { _ in
						isDragging = false
						anchor = nil
					}
			)
		}
		.frame(height: 240)
		.accessibilityElement()
		.accessibilityLabel("Position")
		.accessibilityValue("Pan \(pan.formatted(.percent.precision(.fractionLength(0)))), tilt \(tilt.formatted(.percent.precision(.fractionLength(0))))")
		.sensoryFeedback(.selection, trigger: isDragging)
		.overlay(alignment: .topTrailing) {
			Toggle(isOn: $isFine) {
				Label("Fine", systemImage: "scope")
					.labelStyle(.iconOnly)
			}
			.toggleStyle(.button)
			.buttonStyle(.glass)
			.buttonBorderShape(.circle)
			.labelStyle(.iconOnly)
			.controlSize(.small)
			.padding(8)
		}
	}
}
