import SwiftUI

struct StrobePad: View {
	let glow: Color
	let hertz: Double?
	
	@State private var isLit = false
	
	var body: some View {
		ZStack {
			Stage()
			
			Circle()
				.fill(glow)
				.frame(width: 54)
				.opacity(hertz == nil ? 0.2 : isLit ? 1 : 0.1)
			
			VStack {
				Spacer()
				
				Text(hertz.map { "\($0.formatted(.number.precision(.fractionLength(1)))) Hz" } ?? "Not strobing")
					.font(.caption.monospacedDigit())
					.foregroundStyle(.white.opacity(0.7))
					.padding(.bottom, 8)
			}
		}
		.frame(height: 110)
		.task(id: hertz) {
			guard let hertz else { return }
			
			while !Task.isCancelled {
				isLit.toggle()
				try? await Task.sleep(for: .seconds(max(0.05, 1 / max(0.5, hertz)) / 2))
			}
		}
		.accessibilityElement()
		.accessibilityLabel("Strobe")
		.accessibilityValue(hertz.map { "\($0.formatted(.number.precision(.fractionLength(1)))) hertz" } ?? "Not strobing")
	}
}
