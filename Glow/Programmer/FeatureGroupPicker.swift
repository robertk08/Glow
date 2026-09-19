import SwiftUI

struct FeatureGroupPicker: View {
	let programmer: Programmer
	
	@Binding var group: FeatureGroup
	
	var body: some View {
		ScrollView(.horizontal) {
			HStack(spacing: 8) {
				ForEach(programmer.groups) { option in
					Button {
						group = option
					} label: {
						Label(option.name, systemImage: option.symbol)
							.font(.subheadline.weight(.medium))
					}
					.buttonStyle(.glass)
					.buttonBorderShape(.capsule)
					.tint(group == option ? Color.accentColor : nil)
					.accessibilityAddTraits(group == option ? .isSelected : [])
				}
			}
			.padding(.horizontal)
			.padding(.vertical, 6)
		}
		.scrollIndicators(.hidden)
		.sensoryFeedback(.selection, trigger: group)
	}
}
