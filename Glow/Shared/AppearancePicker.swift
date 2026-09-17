import SwiftUI

struct AppearancePicker: View {
	let symbols: [String]
	
	@Binding var symbol: String
	
	var tint: Binding<FixtureTint>?
	
	private let columns = [GridItem(.adaptive(minimum: 44), spacing: 12)]
	
	var body: some View {
		LazyVGrid(columns: columns, spacing: 12) {
			ForEach(symbols, id: \.self) { option in
				Button {
					symbol = option
				} label: {
					Image(systemName: option)
						.font(.title3)
						.foregroundStyle(symbol == option ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
						.frame(width: 44, height: 44)
						.background(symbol == option ? Color.accentColor.opacity(0.18) : .clear, in: .circle)
				}
				.buttonStyle(.plain)
				.accessibilityLabel(option)
				.accessibilityAddTraits(symbol == option ? [.isButton, .isSelected] : .isButton)
			}
		}
		.padding(.vertical, 4)
		
		if let tint {
			Picker("Colour", selection: tint) {
				ForEach(FixtureTint.allCases) { option in
					Label(option.name, systemImage: option == .none ? "circle.slash" : "circle.fill")
						.tint(option.color ?? .secondary)
						.tag(option)
				}
			}
			.pickerStyle(.palette)
			.paletteSelectionEffect(.automatic)
		}
	}
}
