import SwiftUI

struct GoboPad: View {
	let shape: GoboShape?
	let label: String
	let tint: Color
	let angle: Angle
	let turns: Double?

	var body: some View {
		ZStack {
			Stage()

			if let shape {
				GoboMark(shape: shape, size: 112, tint: tint, angle: angle, turns: turns, backdrop: false)
			} else {
				Circle()
					.fill(tint.opacity(0.9))
					.frame(width: 96)
					.blur(radius: 1)
			}

			VStack {
				Spacer()

				Text(label)
					.font(.caption)
					.foregroundStyle(.white.opacity(0.7))
					.padding(.bottom, 8)
			}
		}
		.frame(height: 160)
	}
}
