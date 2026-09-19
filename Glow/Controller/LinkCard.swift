import SwiftUI

struct LinkCard: View {
	@Environment(Console.self) private var console
	
	var body: some View {
		HStack(spacing: 14) {
			Image(systemName: console.link.symbol)
				.font(.title2)
				.foregroundStyle(console.link.tint)
				.symbolEffect(.variableColor.iterative, isActive: console.link == .connecting)
				.frame(width: 46, height: 46)
				.background(console.link.tint.opacity(0.15), in: .circle)
			
			VStack(alignment: .leading, spacing: 2) {
				Text(console.node?.name ?? console.endpoint.name)
					.font(.headline)
				
				Text(console.link.summary(latency: console.latency))
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.contentTransition(.numericText())
			}
			
			Spacer()
		}
		.padding(.vertical, 6)
		.contentShape(.rect)
		.accessibilityElement(children: .combine)
	}
}
