import SwiftUI

struct StrobePad: View {
	let glow: Color
	let hertz: Double?
	let isRunning: Bool
	
	@State private var isLit = false
	
	var body: some View {
		let period = max(0.05, 1 / max(0.5, hertz ?? 1))
		
		return ZStack {
			Stage()
			
			Circle()
				.fill(glow)
				.frame(width: 54)
				.opacity(isRunning ? (isLit ? 1 : 0.1) : 0.2)
				.animation(.linear(duration: period / 2), value: isLit)
			
			VStack {
				Spacer()
				
				Text(hertz.map { "\($0.formatted(.number.precision(.fractionLength(1)))) Hz" } ?? "Not strobing")
					.font(.caption.monospacedDigit())
					.foregroundStyle(.white.opacity(0.7))
					.padding(.bottom, 8)
			}
		}
		.frame(height: 110)
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
		.accessibilityElement()
		.accessibilityLabel("Strobe")
		.accessibilityValue(hertz.map { "\($0.formatted(.number.precision(.fractionLength(1)))) hertz" } ?? "Not strobing")
	}
}
