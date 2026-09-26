import Foundation

nonisolated struct CueList: Sendable {
	nonisolated struct Light: Sendable {
		let start: DMXAddress
		let type: FixtureType
	}
	
	nonisolated struct Spot: Sendable, Identifiable {
		let id: String
		let light: LightColor
		let level: Double
	}
	
	let scene: String
	let loops: Bool
	let cues: [ShowContents.Cue]
	
	private let states: [Levels]
	private let owned: Levels
	private let lights: [String: Light]
	private let order: [String]
	
	@MainActor init(_ look: Look, cues: [Cue], fixtures: [Fixture], library: FixtureLibrary) {
		scene = look.identifier
		loops = look.loops
		self.cues = look.cues(among: cues).map(\.entry)
		order = fixtures.map(\.identifier)
		
		var tracked = Levels()
		var states: [Levels] = []
		
		for cue in self.cues {
			tracked = tracked.merging(Levels(cue.levels) ?? Levels())
			states.append(tracked)
		}
		
		self.states = states
		owned = tracked
		
		var lights: [String: Light] = [:]
		
		for fixture in fixtures {
			guard let type = library.type(fixture.typeID) else { continue }
			lights[fixture.identifier] = Light(start: fixture.start, type: type)
		}
		
		self.lights = lights
	}
	
	func index(of identifier: String?) -> Int? {
		cues.firstIndex { $0.identifier == identifier }
	}
	
	func next(after index: Int?) -> Int? {
		guard let index else { return cues.isEmpty ? nil : 0 }
		if index + 1 < cues.count { return index + 1 }
		return loops && cues.count > 1 ? 0 : nil
	}
	
	func upcoming(after index: Int?) -> Int? {
		next(after: index) ?? (cues.count == 1 ? 0 : nil)
	}
	
	func summary(at index: Int?) -> String {
		guard let first = cues.first else { return "No cues" }
		
		guard cues.count > 1 else {
			let lights = states[0].lights.count == 1 ? "1 light" : "\(states[0].lights.count) lights"
			return first.fade > 0 ? "\(lights) · \(Cue.seconds(first.fade))" : lights
		}
		
		guard let index else { return loops ? "\(cues.count) cues, looping" : "\(cues.count) cues" }
		return "\(index + 1) of \(cues.count) · \(cues[index].title)"
	}
	
	func previous(before index: Int) -> Int? {
		if index > 0 { return index - 1 }
		return loops && cues.count > 1 ? cues.count - 1 : nil
	}
	
	func follower(of index: Int) -> Int? {
		guard let next = next(after: index), cues[next].trigger != .go else { return nil }
		return next
	}
	
	func tracked(at index: Int) -> Levels {
		states[index]
	}
	
	func ramps(at index: Int) -> [Ramp] {
		let state = tracked(at: index)
		var ramps: [Ramp] = []
		
		for (identifier, slots) in owned.lights {
			guard let light = lights[identifier] else { continue }
			let values = values(of: light, holding: state.lights[identifier] ?? [:])
			var covered: Set<Int> = []
			
			for channel in light.type.channels {
				let stored = channel.offsets.filter { slots[$0] != nil }
				covered.formUnion(channel.offsets)
				guard !stored.isEmpty else { continue }
				
				var kind = channel.attribute.fades ? Ramp.Kind.fade : .snap
				
				if case let .band(dimmer, from, to, open) = light.type.dimming, dimmer.offset == channel.offset {
					kind = .band(from: from, to: to, open: open)
				}
				
				guard stored.count == 2, let fine = channel.fineOffset, let address = light.start.offset(by: channel.offset - 1) else {
					for slot in stored {
						guard let address = light.start.offset(by: slot - 1) else { continue }
						ramps.append(Ramp(address: address, target: Int(values[slot - 1]), kind: kind))
					}
					continue
				}
				
				ramps.append(Ramp(address: address, fine: light.start.offset(by: fine - 1), target: Int(values[channel.offset - 1]) * 256 + Int(values[fine - 1]), kind: kind))
			}
			
			for slot in slots.keys where !covered.contains(slot) && slot <= values.count {
				guard let address = light.start.offset(by: slot - 1) else { continue }
				ramps.append(Ramp(address: address, target: Int(values[slot - 1]), kind: .snap))
			}
		}
		
		return ramps
	}
	
	func spots(at index: Int) -> [Spot] {
		guard cues.indices.contains(index) else { return [] }
		let state = tracked(at: index)
		
		return order.compactMap { identifier in
			guard let slots = state.lights[identifier], let light = lights[identifier] else { return nil }
			let values = values(of: light, holding: slots)
			return Spot(id: identifier, light: light.type.light(in: values), level: light.type.level(in: values))
		}
	}
	
	private func values(of light: Light, holding slots: [Int: UInt8]) -> [UInt8] {
		var values = light.type.defaults
		
		for (slot, value) in slots where slot <= values.count {
			values[slot - 1] = value
		}
		
		return values
	}
}
