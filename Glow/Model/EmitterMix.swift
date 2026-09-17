import Foundation

nonisolated enum ColorMixing: String, Decodable, Sendable {
	case additive, subtractive
}

nonisolated enum Emitter {
	static let mixingOrder: [ChannelRole] = [
		.white, .amber, .lime, .cyan, .magenta, .yellow, .red, .green, .blue,
	]
	
	static let flags: [ChannelRole] = [.cyan, .magenta, .yellow]
	
	static func light(of role: ChannelRole) -> LightColor? {
		switch role {
		case .red: LightColor(red: 1, green: 0, blue: 0)
		case .green: LightColor(red: 0, green: 1, blue: 0)
		case .blue: LightColor(red: 0, green: 0, blue: 1)
		case .white: LightColor(red: 1, green: 0.96, blue: 0.92)
		case .amber: LightColor(red: 1, green: 0.55, blue: 0)
		case .lime: LightColor(red: 0.72, green: 1, blue: 0.16)
		case .cyan: LightColor(red: 0, green: 1, blue: 1)
		case .magenta: LightColor(red: 1, green: 0, blue: 1)
		case .yellow: LightColor(red: 1, green: 1, blue: 0)
		case .uv: LightColor(red: 0.28, green: 0, blue: 0.85)
		default: nil
		}
	}
}

nonisolated struct EmitterMix: Equatable, Sendable {
	private var levels: [ChannelRole: Double]
	
	init(_ levels: [ChannelRole: Double] = [:]) {
		self.levels = levels
	}
	
	subscript(role: ChannelRole) -> Double {
		get { levels[role] ?? 0 }
		set { levels[role] = newValue }
	}
	
	var peak: Double { levels.values.max() ?? 0 }
	
	var normalised: EmitterMix {
		let peak = peak
		guard peak > 0 else { return self }
		return EmitterMix(levels.mapValues { $0 / peak })
	}
	
	func light(_ mixing: ColorMixing) -> LightColor {
		guard mixing == .additive else {
			return LightColor(red: 1 - self[.cyan], green: 1 - self[.magenta], blue: 1 - self[.yellow]).clamped
		}
		
		return levels.reduce(LightColor.black) { total, entry in
			guard let emitter = Emitter.light(of: entry.key) else { return total }
			return total + emitter * entry.value
		}
	}
	
	static func mixing(_ target: LightColor, emitters available: [ChannelRole], mixing: ColorMixing) -> EmitterMix {
		guard mixing == .additive else {
			let wanted = target.normalised.clamped
			return EmitterMix([.cyan: 1 - wanted.red, .magenta: 1 - wanted.green, .yellow: 1 - wanted.blue])
		}
		
		let emitters = available.filter { $0 != .uv && Emitter.light(of: $0) != nil }
		guard !emitters.isEmpty else { return EmitterMix() }
		
		var residual = target.normalised.clamped
		var mix = EmitterMix()
		
		for role in Emitter.mixingOrder where emitters.contains(role) {
			guard let emitter = Emitter.light(of: role) else { continue }
			
			var amount = Double.infinity
			for (component, share) in [
				(residual.red, emitter.red), (residual.green, emitter.green), (residual.blue, emitter.blue),
			] where share > 0 {
				amount = min(amount, component / share)
			}
			
			guard amount.isFinite, amount > 0 else { continue }
			amount = min(amount, 1)
			mix[role] = amount
			residual = (residual - emitter * amount).clamped
		}
		
		guard mix.peak > 0 else { return closestDirection(to: target, emitters: emitters) }
		return mix.normalised
	}
	
	static func white(kelvin: Double, emitters available: [ChannelRole], mixing: ColorMixing) -> EmitterMix {
		self.mixing(ColorTemperature.light(kelvin: kelvin), emitters: available, mixing: mixing)
	}
	
	private static func closestDirection(to target: LightColor, emitters: [ChannelRole]) -> EmitterMix {
		var mix = EmitterMix()
		let direction = target.normalised
		
		for role in emitters {
			guard let emitter = Emitter.light(of: role) else { continue }
			let magnitude = emitter.dot(emitter)
			guard magnitude > 0 else { continue }
			mix[role] = (direction.dot(emitter) / magnitude).clampedToUnit
		}
		
		return mix.normalised
	}
}

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
		case let .white(kelvin): ColorTemperature.light(kelvin: kelvin)
		case let .colour(light): light
		case .ultraviolet: Emitter.light(of: .uv) ?? .black
		}
	}
	
	func mix(emitters: [ChannelRole], mixing: ColorMixing) -> EmitterMix {
		switch recipe {
		case let .white(kelvin): .white(kelvin: kelvin, emitters: emitters, mixing: mixing)
		case let .colour(light): .mixing(light, emitters: emitters, mixing: mixing)
		case .ultraviolet: EmitterMix([.uv: 1])
		}
	}
	
	static func all(emitters: [ChannelRole]) -> [ColorPreset] {
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
