import Foundation

nonisolated struct ColorPreset: Identifiable, Equatable, Sendable {
	nonisolated enum Recipe: Equatable, Sendable {
		case white(kelvin: Double)
		case colour(LightColor)
		case ultraviolet
	}
	
	let name: String
	let recipe: Recipe
	
	var id: String { name }
	
	var swatch: LightColor {
		switch recipe {
		case let .white(kelvin): ColorTemperature.swatch(kelvin: kelvin)
		case let .colour(light): light
		case .ultraviolet: Emitter.light(of: .uv) ?? .black
		}
	}
	
	func mix(emitters: [Attribute], mixing: ColorMixing) -> EmitterMix {
		switch recipe {
		case let .white(kelvin): .white(kelvin: kelvin, emitters: emitters, mixing: mixing)
		case let .colour(light): .mixing(light, emitters: emitters, mixing: mixing)
		case .ultraviolet: EmitterMix([.uv: 1])
		}
	}
	
	static func all(emitters: [Attribute]) -> [ColorPreset] {
		var presets: [ColorPreset] = [
			ColorPreset(name: "Warm white", recipe: .white(kelvin: ColorTemperature.warm)),
			ColorPreset(name: "Neutral white", recipe: .white(kelvin: ColorTemperature.neutral)),
			ColorPreset(name: "Cool white", recipe: .white(kelvin: ColorTemperature.cool)),
			ColorPreset(name: "Red", recipe: .colour(LightColor(hue: 0, saturation: 1))),
			ColorPreset(name: "Amber", recipe: .colour(LightColor(hue: 0.105, saturation: 1))),
			ColorPreset(name: "Gold", recipe: .colour(LightColor(hue: 0.13, saturation: 0.62))),
			ColorPreset(name: "Pink", recipe: .colour(LightColor(hue: 0.94, saturation: 0.45))),
			ColorPreset(name: "Magenta", recipe: .colour(LightColor(hue: 0.86, saturation: 1))),
			ColorPreset(name: "Lavender", recipe: .colour(LightColor(hue: 0.75, saturation: 0.45))),
			ColorPreset(name: "Blue", recipe: .colour(LightColor(hue: 0.62, saturation: 1))),
			ColorPreset(name: "Cyan", recipe: .colour(LightColor(hue: 0.5, saturation: 1))),
			ColorPreset(name: "Green", recipe: .colour(LightColor(hue: 0.33, saturation: 1))),
		]
		
		if emitters.contains(.uv) {
			presets.append(ColorPreset(name: "UV", recipe: .ultraviolet))
		}
		
		return presets
	}
}
