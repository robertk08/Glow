import SwiftUI

@MainActor
struct GroupControl {
	let controls: [FixtureControl]
	
	var dims: Bool { controls.contains { $0.dims } }
	var mixesColor: Bool { controls.contains { $0.profile.mixesColor } }
	var movesHead: Bool { controls.contains { $0.profile.movesHead } }
	
	var brightness: Double {
		let dimmable = controls.filter(\.dims)
		guard !dimmable.isEmpty else { return 0 }
		return dimmable.map(\.brightness).reduce(0, +) / Double(dimmable.count)
	}
	
	var brightnessBinding: Binding<Double> {
		Binding { brightness } set: { level in
			for control in controls where control.dims {
				control.brightness = level
			}
		}
	}
	
	var displayColor: Color {
		controls.first { $0.profile.mixesColor }?.displayColor ?? .accentColor
	}
	
	func apply(_ preset: ColorPreset) {
		for control in controls where control.profile.mixesColor {
			control.apply(preset.mix(with: control.profile.emitterChannels.map(\.role)))
		}
	}
	
	func apply(hue: Double, saturation: Double) {
		let light = LightColor(hue: hue, saturation: saturation)
		for control in controls where control.profile.mixesColor {
			control.apply(.mixing(light, with: control.profile.emitterChannels.map(\.role)))
		}
	}
	
	func setFraction(_ value: Double, for role: ChannelRole) {
		for control in controls {
			control.setFraction(value, for: role)
		}
	}
	
	func home() {
		for control in controls {
			control.home()
		}
	}
}
