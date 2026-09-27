import Foundation

nonisolated struct CueList: Sendable {
	nonisolated struct Light: Sendable {
		let start: DMXAddress
		let type: FixtureType
	}
	
	let scene: String
	let tap: SceneAction
	let cues: [ShowContents.Cue]
	
	private let states: [Levels]
	private let owned: Levels
	private let lights: [String: Light]
	
	@MainActor init(_ look: Look, cues: [Cue], fixtures: [Fixture], library: FixtureLibrary) {
		scene = look.identifier
		tap = look.tap
		self.cues = look.cues(among: cues).map(\.entry)
		
		var lights: [String: Light] = [:]
		
		for fixture in fixtures {
			guard let type = library.type(fixture.typeID) else { continue }
			lights[fixture.identifier] = Light(start: fixture.start, type: type)
		}
		
		var tracked = Levels()
		var states: [Levels] = []
		
		for cue in self.cues {
			tracked = tracked.merging(Levels(cue.levels) ?? Levels())
			states.append(tracked)
		}
		
		self.lights = lights
		self.states = states
		owned = tracked
	}
	
	func index(of identifier: String?) -> Int? {
		cues.firstIndex { $0.identifier == identifier }
	}
	
	func next(after index: Int?) -> Int? {
		guard !cues.isEmpty else { return nil }
		guard let index else { return 0 }
		return (index + 1) % cues.count
	}
	
	func previous(before index: Int) -> Int? {
		guard !cues.isEmpty else { return nil }
		return (index + cues.count - 1) % cues.count
	}
	
	func title(at index: Int) -> String {
		cues[index].label.isEmpty ? "Cue \(index + 1)" : cues[index].label
	}
	
	func status(at index: Int?) -> String {
		guard cues.count > 1 else { return index == nil ? (tap == .flash ? "Hold to flash" : "Off") : "On" }
		guard let index else { return "\(cues.count) cues, tap to start" }
		return "\(index + 1) · \(title(at: index))"
	}
	
	var addresses: Set<Int> {
		var found: Set<Int> = []
		
		for (identifier, slots) in owned.lights {
			guard let light = lights[identifier] else { continue }
			
			for slot in slots.keys {
				guard let address = light.start.offset(by: slot - 1) else { continue }
				found.insert(address.value)
			}
		}
		
		return found
	}
	
	func ramps(at index: Int?, holding held: [Int: UInt8]) -> [Ramp] {
		let state = index.map { states[$0] } ?? Levels()
		var ramps: [Ramp] = []
		
		for (identifier, slots) in owned.lights {
			guard let light = lights[identifier] else { continue }
			let stored = state.lights[identifier] ?? [:]
			var covered: Set<Int> = []
			
			for channel in light.type.channels {
				let offsets = channel.offsets.filter { slots[$0] != nil }
				covered.formUnion(channel.offsets)
				guard !offsets.isEmpty else { continue }
				
				var kind = channel.attribute.fades ? Ramp.Kind.fade : .snap
				
				if case let .band(dimmer, from, to, open) = light.type.dimming, dimmer.offset == channel.offset {
					kind = .band(from: from, to: to, open: open)
				}
				
				guard offsets.count == 2, let fine = channel.fineOffset, let coarse = light.start.offset(by: channel.offset - 1), let low = light.start.offset(by: fine - 1) else {
					for slot in offsets {
						guard let address = light.start.offset(by: slot - 1), let target = stored[slot] ?? held[address.value] else { continue }
						ramps.append(Ramp(address: address, target: Int(target), kind: kind))
					}
					continue
				}
				
				guard let high = stored[channel.offset] ?? held[coarse.value], let small = stored[fine] ?? held[low.value] else { continue }
				ramps.append(Ramp(address: coarse, fine: low, target: Int(high) * 256 + Int(small), kind: kind))
			}
			
			for slot in slots.keys where !covered.contains(slot) {
				guard let address = light.start.offset(by: slot - 1), let target = stored[slot] ?? held[address.value] else { continue }
				ramps.append(Ramp(address: address, target: Int(target), kind: .snap))
			}
		}
		
		return ramps
	}
}
