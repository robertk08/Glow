import SwiftUI

struct SwatchPicker: View {
	@Binding var colors: [String]

	private var first: Binding<Color> {
		Binding { (colors.first.flatMap(LightColor.init(hex:)) ?? LightColor(red: 1, green: 1, blue: 1)).color } set: { picked in
			if colors.isEmpty {
				colors = [LightColor(picked).hex]
			} else {
				colors[0] = LightColor(picked).hex
			}
		}
	}

	private var second: Binding<Color> {
		Binding { (colors.count > 1 ? LightColor(hex: colors[1]) : nil)?.color ?? LightColor(red: 1, green: 1, blue: 1).color } set: { picked in
			guard colors.count > 1 else { return }
			colors[1] = LightColor(picked).hex
		}
	}

	var body: some View {
		ColorPicker("Color", selection: first, supportsOpacity: false)

		if colors.count > 1 {
			ColorPicker("Second Color", selection: second, supportsOpacity: false)

			Button("Remove Second Color", role: .destructive) {
				colors.removeLast()
			}
		}

		if colors.count == 1 {
			Button("Add a Second Color") {
				colors.append(colors[0])
			}
		}

		if !colors.isEmpty {
			Button("No Color", role: .destructive) {
				colors = []
			}
		}
	}
}
