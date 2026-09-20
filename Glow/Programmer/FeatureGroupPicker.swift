import SwiftUI

struct FeatureGroupPicker: View {
	let programmer: Programmer
	
	@Binding var group: FeatureGroup
	
	var body: some View {
		ScrollViewReader { proxy in
			ScrollView(.horizontal) {
				HStack(spacing: 8) {
					ForEach(programmer.groups) { option in
						Toggle(isOn: Binding { group == option } set: { _ in group = option }) {
							Label(option.name, systemImage: option.symbol)
								.font(.subheadline.weight(.medium))
						}
						.toggleStyle(.button)
						.buttonStyle(.glass)
						.buttonBorderShape(.capsule)
						.tint(group == option ? Color.accentColor : nil)
						.id(option)
					}
				}
				.padding(.horizontal)
				.padding(.vertical, 6)
			}
			.scrollIndicators(.hidden)
			.sensoryFeedback(.selection, trigger: group)
			.onChange(of: group) {
				withAnimation {
					proxy.scrollTo(group, anchor: .center)
				}
			}
		}
	}
}
