import SwiftUI

struct Swatch: View {
	let colors: [LightColor]

	var size: CGFloat = 44
	var isSelected = false

	private var fill: LinearGradient {
		let first = colors.first ?? .black
		let second = colors.count > 1 ? colors[1] : first

		return LinearGradient(stops: [
			.init(color: first.color, location: 0),
			.init(color: first.color, location: 0.5),
			.init(color: second.color, location: 0.5),
			.init(color: second.color, location: 1),
		], startPoint: .leading, endPoint: .trailing)
	}

	var body: some View {
		Circle()
			.fill(fill)
			.frame(width: size, height: size)
			.overlay {
				Circle()
					.strokeBorder(.separator)
			}
			.overlay {
				Image(systemName: "checkmark")
					.font(.headline)
					.foregroundStyle(colors.first?.contrastingInk ?? .white)
					.opacity(isSelected ? 1 : 0)
			}
	}
}
