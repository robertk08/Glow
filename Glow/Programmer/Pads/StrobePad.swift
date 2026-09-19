import SwiftUI

struct StrobePad: View {
	@Binding var rate: Double
	
	let glow: Color
	let hertz: Double?
	let isRunning: Bool
	
	@State private var isLit = false
	
	var body: some View {
		let period = max(0.05, 1 / max(0.5, hertz ?? 1))
		
		return VStack(spacing: 12) {
			ZStack {
				RoundedRectangle(cornerRadius: 18, style: .continuous)
					.fill(.fill.quaternary)
				
				Circle()
					.fill(glow)
					.frame(width: 54)
					.opacity(isRunning ? (isLit ? 1 : 0.12) : 0.25)
					.animation(.linear(duration: period / 2), value: isLit)
				
				if !isRunning {
					Image(systemName: "bolt.slash")
						.font(.title3)
						.foregroundStyle(.secondary)
				}
			}
			.frame(height: 92)
			
			LabeledContent("Rate") {
				Text(hertz.map { "\($0.formatted(.number.precision(.fractionLength(1)))) Hz" } ?? "Off")
					.monospacedDigit()
					.foregroundStyle(.secondary)
			}
			.font(.subheadline)
			
			Slider(value: $rate, in: 0...1) {
				Text("Strobe rate")
			}
		}
		.task(id: period) {
			guard isRunning else { return }
			
			while !Task.isCancelled {
				isLit.toggle()
				try? await Task.sleep(for: .seconds(period / 2))
			}
		}
		.onChange(of: isRunning) {
			isLit = false
		}
		.sensoryFeedback(.selection, trigger: isRunning)
	}
}
