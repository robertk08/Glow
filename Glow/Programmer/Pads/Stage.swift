import SwiftUI

struct Stage: View {
	var body: some View {
		RoundedRectangle(cornerRadius: 18, style: .continuous)
			.fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.06)], startPoint: .top, endPoint: .bottom))
			.overlay {
				RoundedRectangle(cornerRadius: 18, style: .continuous)
					.strokeBorder(.white.opacity(0.12))
			}
	}
}
