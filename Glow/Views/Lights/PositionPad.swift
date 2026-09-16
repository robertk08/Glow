import SwiftUI

struct PositionPad: View {
    @Binding var pan: Double
    @Binding var tilt: Double

    @State private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let position = CGPoint(x: pan * size.width, y: (1 - tilt) * size.height)

            ZStack {
                Rectangle()
                    .fill(.fill.tertiary)

                Path { path in
                    path.move(to: CGPoint(x: size.width / 2, y: 0))
                    path.addLine(to: CGPoint(x: size.width / 2, y: size.height))
                    path.move(to: CGPoint(x: 0, y: size.height / 2))
                    path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                }
                .stroke(.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                Circle()
                    .fill(.tint)
                    .frame(width: isDragging ? 32 : 24)
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
        .frame(height: 220)
        .sensoryFeedback(.selection, trigger: isDragging)
        .accessibilityElement()
        .accessibilityLabel("Position")
        .accessibilityValue("Pan \(Int(pan * 100)) percent, tilt \(Int(tilt * 100)) percent")
    }
}
