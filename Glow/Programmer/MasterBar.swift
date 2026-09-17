import SwiftUI

struct MasterBar: View {
	@Environment(Console.self) private var console
	
	var body: some View {
		@Bindable var console = console
		
		return HStack(spacing: 12) {
			Image(systemName: "sun.max")
				.foregroundStyle(.secondary)
			
			Slider(value: $console.master, in: 0...1, neutralValue: 1) {
				Text("Master")
			}
			.frame(minWidth: 140)
			
			Text(console.master, format: .percent.precision(.fractionLength(0)))
				.font(.caption.monospacedDigit())
				.foregroundStyle(.secondary)
				.frame(width: 40, alignment: .trailing)
			
			Button {
				console.blackout.toggle()
			} label: {
				Image(systemName: "power")
					.font(.title3)
					.foregroundStyle(console.blackout ? Color.white : Color.primary)
					.frame(width: 32, height: 32)
					.background(console.blackout ? Color.red : Color.clear, in: .circle)
					.frame(width: 44, height: 40)
					.contentShape(.rect)
			}
			.buttonStyle(.plain)
		}
		.frame(maxWidth: 520)
		.padding(.horizontal, 12)
		.sensoryFeedback(.impact(weight: .heavy), trigger: console.blackout)
	}
}
