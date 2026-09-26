import SwiftUI

struct SpotStrip: View {
	let spots: [CueList.Spot]
	
	var size: CGFloat = 14
	var limit = 10
	
	var body: some View {
		HStack(spacing: -size * 0.25) {
			ForEach(spots.prefix(limit)) { spot in
				Circle()
					.fill(spot.level > 0 ? spot.light.color.opacity(0.35 + spot.level * 0.65) : Color(.tertiarySystemFill))
					.frame(width: size, height: size)
					.overlay {
						Circle()
							.strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
					}
					.shadow(color: spot.level > 0.5 ? spot.light.color.opacity(0.6) : .clear, radius: size * 0.3)
			}
			
			if spots.count > limit {
				Text("+\(spots.count - limit)")
					.font(.caption2.weight(.semibold))
					.foregroundStyle(.secondary)
					.padding(.leading, size * 0.5)
			}
		}
		.accessibilityHidden(true)
	}
}
