import Foundation

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
			mix[role] = min(max(direction.dot(emitter) / magnitude, 0), 1)
		}
		
		return mix.normalised
	}
}
