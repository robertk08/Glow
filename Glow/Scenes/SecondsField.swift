import SwiftUI

struct SecondsField: View {
	let title: String
	let symbol: String
	
	@Binding var seconds: Double
	
	var body: some View {
		LabeledContent {
			HStack(spacing: 4) {
				TextField(title, value: Binding { seconds == 0 ? nil : seconds } set: { seconds = $0 ?? 0 }, format: .number.precision(.fractionLength(0...1)), prompt: Text("0"))
					.keyboardType(.decimalPad)
					.multilineTextAlignment(.trailing)
					.monospacedDigit()
				
				Text("s")
					.foregroundStyle(.secondary)
			}
		} label: {
			Label(title, systemImage: symbol)
		}
	}
}
