import SwiftUI

struct IconPicker: View {
	let symbols: [String]
	
	@Binding var symbol: String
	
	private let columns = [GridItem(.adaptive(minimum: 44), spacing: 12)]
	
	var body: some View {
		LazyVGrid(columns: columns, spacing: 12) {
			ForEach(symbols, id: \.self) { option in
				Button {
					symbol = option
				} label: {
					Image(systemName: option)
						.font(.title3)
						.frame(width: 44, height: 44)
						.background(symbol == option ? Color.accentColor.opacity(0.2) : .clear, in: .circle)
				}
				.buttonStyle(.plain)
			}
		}
		.padding(.vertical, 4)
	}
}
