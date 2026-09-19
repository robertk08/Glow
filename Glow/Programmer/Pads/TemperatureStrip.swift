import SwiftUI

struct TemperatureStrip: View {
	@Binding var kelvin: Double
	
	@State private var isDragging = false
	
	private let stops: [Color] = stride(from: ColorTemperature.range.lowerBound, through: ColorTemperature.range.upperBound, by: 500)
		.map { ColorTemperature.swatch(kelvin: $0).color }
	
	var body: some View {
		let span = ColorTemperature.range.upperBound - ColorTemperature.range.lowerBound
		let share = (kelvin - ColorTemperature.range.lowerBound) / span
		
		return GeometryReader { proxy in
			let width = proxy.size.width
			
			ZStack(alignment: .leading) {
				Capsule()
					.fill(LinearGradient(colors: stops, startPoint: .leading, endPoint: .trailing))
				
				Capsule()
					.fill(.white)
					.frame(width: 6)
					.padding(.vertical, 3)
					.shadow(radius: 2)
					.offset(x: min(max(share * width - 3, 0), width - 6))
			}
			.contentShape(.rect)
			.gesture(
				DragGesture(minimumDistance: 0)
					.onChanged { drag in
						isDragging = true
						kelvin = ColorTemperature.range.lowerBound + min(max(drag.location.x / width, 0), 1) * span
					}
					.onEnded { _ in isDragging = false }
			)
		}
		.frame(height: 34)
		.accessibilityElement()
		.accessibilityLabel("White balance")
		.accessibilityValue("\(Int(kelvin)) kelvin")
		.sensoryFeedback(.selection, trigger: isDragging)
	}
}
