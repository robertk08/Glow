import SwiftUI

struct AppearancePicker: View {
	let symbols: [String]
	
	@Binding var symbol: String
	
	var tint: Binding<FixtureTint>?
	
	private let symbolColumns = [GridItem(.adaptive(minimum: 44), spacing: 12)]
	private let tintColumns = [GridItem(.adaptive(minimum: 40), spacing: 10)]
	
	var body: some View {
		LazyVGrid(columns: symbolColumns, spacing: 12) {
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
			LazyVGrid(columns: tintColumns, spacing: 10) {
				ForEach(FixtureTint.allCases) { option in
					Button {
						tint.wrappedValue = option
					} label: {
						Circle()
							.fill(option.color ?? Color(.tertiarySystemFill))
							.frame(width: 30, height: 30)
							.overlay {
								Image(systemName: "slash.circle")
									.font(.footnote)
									.foregroundStyle(.secondary)
									.opacity(option == .none ? 1 : 0)
							}
							.padding(4)
							.overlay {
								Circle()
									.strokeBorder(.tint, lineWidth: tint.wrappedValue == option ? 2 : 0)
							}
					}
					.buttonStyle(.plain)
					.accessibilityLabel(option.name)
					.accessibilityAddTraits(tint.wrappedValue == option ? [.isButton, .isSelected] : .isButton)
				}
			}
			.padding(.vertical, 4)
		}
	}
}
