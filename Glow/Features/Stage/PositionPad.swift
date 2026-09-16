import SwiftUI

/// A pan/tilt pad. Dragging moves the head; the crosshair is where it is.
///
/// Two faders would be more precise and much worse: pointing a light is a
/// spatial task, and people do it by looking at the wall, not at numbers.
struct PositionPad: View {
    @Binding var pan: Double
    @Binding var tilt: Double
    var panDegrees: Double?
    var tiltDegrees: Double?

    @State private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            // Tilt runs bottom-to-top: up on the pad points the head up.
            let position = CGPoint(
                x: pan * size.width,
                y: (1 - tilt) * size.height
            )

            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.background.secondary)

                Path { path in
                    path.move(to: CGPoint(x: size.width / 2, y: 0))
                    path.addLine(to: CGPoint(x: size.width / 2, y: size.height))
                    path.move(to: CGPoint(x: 0, y: size.height / 2))
                    path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                }
                .stroke(.quaternary, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                Circle()
                    .fill(.tint)
                    .frame(width: isDragging ? 34 : 26)
                    .overlay {
                        Circle().strokeBorder(.background, lineWidth: 3)
                    }
                    .shadow(radius: isDragging ? 8 : 3)
                    .position(position)
                    .animation(.snappy(duration: 0.15), value: isDragging)
            }
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        pan = (value.location.x / size.width).clamped(to: 0...1)
                        tilt = (1 - value.location.y / size.height).clamped(to: 0...1)
                    }
                    .onEnded { _ in isDragging = false }
            )
        }
        .aspectRatio(1.4, contentMode: .fit)
        .sensoryFeedback(.selection, trigger: isDragging)
        .accessibilityElement()
        .accessibilityLabel("Position")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            let step = 0.02
            switch direction {
            case .increment: pan = (pan + step).clamped(to: 0...1)
            case .decrement: pan = (pan - step).clamped(to: 0...1)
            @unknown default: break
            }
        }
    }

    private var accessibilityValue: String {
        if let panDegrees, let tiltDegrees {
            let panAngle = Int((pan - 0.5) * panDegrees)
            let tiltAngle = Int((tilt - 0.5) * tiltDegrees)
            return "Pan \(panAngle) degrees, tilt \(tiltAngle) degrees"
        }
        return "Pan \(Int(pan * 100)) percent, tilt \(Int(tilt * 100)) percent"
    }
}
