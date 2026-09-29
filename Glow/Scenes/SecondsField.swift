import SwiftUI

struct SecondsField: View {
	let title: LocalizedStringKey
	
	@Binding var seconds: Double
	
	var body: some View {
		LabeledContent(title) {
			HStack(spacing: 4) {
				TextField(title, value: Binding { seconds == 0 ? nil : seconds } set: { seconds = $0 ?? 0 }, format: .number.precision(.fractionLength(0...1)), prompt: Text("0"))
					.keyboardType(.decimalPad)
					.multilineTextAlignment(.trailing)
					.monospacedDigit()
				
				Text("s")
					.foregroundStyle(.secondary)
			}
		}
	}
}
