import SwiftUI

struct MasterBar: View {
	@Environment(Console.self) private var console
	
	var body: some View {
		@Bindable var console = console
		
		HStack(spacing: 14) {
			Image(systemName: "sun.max")
				.foregroundStyle(.secondary)
			
			Slider(value: $console.master, in: 0...1) {
				Text("Master")
			}
			
			Text(console.master, format: .percent.precision(.fractionLength(0)))
				.font(.caption.monospacedDigit())
				.foregroundStyle(.secondary)
			
			Image(systemName: "power")
				.font(.title3)
				.foregroundStyle(console.blackout ? Color.red : Color.primary)
				.frame(width: 44, height: 30)
				.contentShape(.rect)
				.gesture(DragGesture(minimumDistance: 0).onChanged { _ in
					console.blackout = true
				}.onEnded { _ in
					console.blackout = false
				})
				.accessibilityLabel("Hold for blackout")
		}
		.frame(maxWidth: 520)
		.padding(.horizontal)
		.sensoryFeedback(.impact(weight: .heavy), trigger: console.blackout)
	}
}
