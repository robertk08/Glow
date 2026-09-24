import SwiftUI

struct PositionPad: View {
	@Binding var pan: Double
	@Binding var tilt: Double

	var panDegrees: Double?
	var tiltDegrees: Double?

	@State private var isDragging = false
	@State private var isFine = false
	@State private var anchor: CGPoint?
	@State private var origin = CGPoint.zero

	private func reading(_ fraction: Double, over degrees: Double?) -> String {
		guard let degrees else { return fraction.formatted(.percent.precision(.fractionLength(0))) }
		return "\((fraction * degrees - degrees / 2).formatted(.number.precision(.fractionLength(0))))°"
	}

	private func widest(_ degrees: Double?) -> String {
		guard let degrees else { return "100%" }
		return "-\((degrees / 2).formatted(.number.precision(.fractionLength(0))))°"
	}
	
	private func axis(_ name: String, _ fraction: Double, over degrees: Double?) -> some View {
		Text("\(name) \(widest(degrees))")
			.hidden()
			.overlay(alignment: .leading) {
				Text("\(name) \(reading(fraction, over: degrees))")
					.contentTransition(.numericText())
			}
	}

	var body: some View {
		VStack(spacing: 8) {
			HStack(spacing: 12) {
				axis("Pan", pan, over: panDegrees)
				axis("Tilt", tilt, over: tiltDegrees)

				Spacer(minLength: 8)

				Toggle(isOn: $isFine) {
					Label("Fine", systemImage: "scope")
				}
				.toggleStyle(.button)
				.buttonStyle(.glass)
				.buttonBorderShape(.circle)
				.labelStyle(.iconOnly)
				.controlSize(.small)
			}
			.font(.caption.monospacedDigit())
			.foregroundStyle(.secondary)
			.padding(.horizontal, 6)

			GeometryReader { proxy in
				let size = proxy.size
				let inset = 16.0
				let field = CGRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
				let position = CGPoint(x: field.minX + pan * field.width, y: field.minY + (1 - tilt) * field.height)

				ZStack {
					RoundedRectangle(cornerRadius: 22, style: .continuous)
						.fill(.fill.quaternary)

					Path { path in
						for step in 1..<4 {
							let x = field.minX + field.width * Double(step) / 4
							let y = field.minY + field.height * Double(step) / 4
							path.move(to: CGPoint(x: x, y: field.minY))
							path.addLine(to: CGPoint(x: x, y: field.maxY))
							path.move(to: CGPoint(x: field.minX, y: y))
							path.addLine(to: CGPoint(x: field.maxX, y: y))
						}
					}
					.stroke(.separator.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))

					Circle()
						.fill(.clear)
						.frame(width: isDragging ? 26 : 24)
						.glassEffect(.regular.tint(.accentColor.opacity(0.35)).interactive(), in: .circle)
						.position(position)
						.animation(.snappy(duration: 0.15), value: isDragging)
				}
				.contentShape(.rect(cornerRadius: 22))
				.gesture(
					DragGesture(minimumDistance: 0)
						.onChanged { drag in
							if anchor != drag.startLocation {
								anchor = drag.startLocation
								origin = CGPoint(x: pan, y: tilt)
								isDragging = true
							}

							guard isFine else {
								pan = min(max((drag.location.x - field.minX) / field.width, 0), 1)
								tilt = min(max(1 - (drag.location.y - field.minY) / field.height, 0), 1)
								return
							}

							pan = min(max(origin.x + drag.translation.width / field.width / 6, 0), 1)
							tilt = min(max(origin.y - drag.translation.height / field.height / 6, 0), 1)
						}
						.onEnded { _ in
							isDragging = false
							anchor = nil
						}
				)
			}
			.frame(height: 220)
			.accessibilityRepresentation {
				Slider(value: $pan, in: 0...1) {
					Text("Pan")
				}

				Slider(value: $tilt, in: 0...1) {
					Text("Tilt")
				}
			}
		}
		.sensoryFeedback(.selection, trigger: isDragging)
	}
}
