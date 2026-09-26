import SwiftUI

struct SecondsPicker: View {
	let title: String
	
	@Binding var seconds: Double
	
	var zero = "0 s"
	
	private let presets: [Double] = [0, 1, 2, 3, 5, 10, 30]
	
	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			Stepper(value: $seconds, in: 0...3600, step: 0.5) {
				LabeledContent(title, value: Cue.seconds(seconds, zero: zero))
			}
			
			ScrollView(.horizontal) {
				HStack(spacing: 8) {
					ForEach(presets, id: \.self) { preset in
						Toggle(isOn: Binding { seconds == preset } set: { _ in seconds = preset }) {
							Text(Cue.seconds(preset, zero: zero))
								.font(.subheadline.weight(.medium))
								.monospacedDigit()
						}
						.toggleStyle(.button)
						.buttonStyle(.glass)
						.buttonBorderShape(.capsule)
						.tint(seconds == preset ? Color.accentColor : nil)
					}
				}
				.padding(.vertical, 2)
			}
			.scrollIndicators(.hidden)
			.sensoryFeedback(.selection, trigger: seconds)
		}
	}
}
