import SwiftUI

@MainActor
struct FixtureControl {
	nonisolated struct Target: Equatable, Sendable {
		let profile: FixtureProfile
		let start: DMXAddress
	}
	
	let targets: [Target]
	let title: String
	let console: Console
	
	init(profile: FixtureProfile, start: DMXAddress, console: Console) {
		targets = [Target(profile: profile, start: start)]
		title = profile.model
		self.console = console
	}
	
	init?(fixture: Fixture, library: FixtureLibrary, console: Console) {
		guard let profile = library.profile(fixture.profileID) else { return nil }
		targets = [Target(profile: profile, start: fixture.start)]
		title = fixture.name
		self.console = console
	}
	
	init(fixtures: [Fixture], library: FixtureLibrary, console: Console) {
		targets = fixtures.compactMap { fixture in
			guard let profile = library.profile(fixture.profileID) else { return nil }
			return Target(profile: profile, start: fixture.start)
		}
		title = fixtures.count == 1 ? fixtures[0].name : "\(fixtures.count) Lights"
		self.console = console
	}
	
	var isEmpty: Bool { targets.isEmpty }
	
	var isSingle: Bool { targets.count == 1 }
	
	var profile: FixtureProfile? {
		guard let first = targets.first, targets.allSatisfy({ $0.profile.id == first.profile.id }) else { return nil }
		return first.profile
	}
	
	private func value(of channel: ProfileChannel, in target: Target) -> UInt8 {
		guard let address = target.start.offset(by: channel.offset - 1) else { return 0 }
		return console.value(at: address)
	}
	
	private func set(_ value: UInt8, of channel: ProfileChannel, in target: Target) {
		guard let address = target.start.offset(by: channel.offset - 1) else { return }
		console.set(value, at: address)
	}
	
	func value(of channel: ProfileChannel) -> UInt8 {
		guard let first = targets.first else { return 0 }
		return value(of: channel, in: first)
	}
	
	func set(_ value: UInt8, of channel: ProfileChannel) {
		for target in targets {
			set(value, of: channel, in: target)
		}
	}
	
	func binding(_ channel: ProfileChannel) -> Binding<Double> {
		Binding { Double(value(of: channel)) } set: { set(UInt8(min(max($0.rounded(), 0), 255)), of: channel) }
	}
	
	func band(of channel: ProfileChannel) -> ChannelRange? {
		channel.range(containing: value(of: channel))
	}
	
	func bands(of channel: ProfileChannel) -> [ChannelRange] {
		guard case let .band(dimmer, from, to, _) = profile?.dimming, dimmer.offset == channel.offset else { return channel.ranges }
		return channel.ranges.filter { $0.from != from || $0.to != to }
	}
	
	func adjustableBand(of channel: ProfileChannel) -> ChannelRange? {
		guard let active = band(of: channel), active.kind == .proportional, bands(of: channel).contains(active) else { return nil }
		return active
	}
	
	private func fraction(_ role: ChannelRole, in target: Target) -> Double {
		guard let coarse = target.profile.channel(role) else { return 0 }
		let high = Double(value(of: coarse, in: target))
		guard let fine = target.profile.channel(role, fine: true) else { return high / 255 }
		return (high * 256 + Double(value(of: fine, in: target))) / 65535
	}
	
	private func setFraction(_ newValue: Double, for role: ChannelRole, in target: Target) {
		guard let coarse = target.profile.channel(role) else { return }
		let clamped = min(max(newValue, 0), 1)
		
		guard let fine = target.profile.channel(role, fine: true) else {
			set(UInt8((clamped * 255).rounded()), of: coarse, in: target)
			return
		}
		
		let combined = UInt16((clamped * 65535).rounded())
		set(UInt8(combined >> 8), of: coarse, in: target)
		set(UInt8(combined & 0xFF), of: fine, in: target)
	}
	
	func fraction(_ role: ChannelRole) -> Double {
		for target in targets where target.profile.channel(role) != nil {
			return fraction(role, in: target)
		}
		
		return 0
	}
	
	func setFraction(_ newValue: Double, for role: ChannelRole) {
		for target in targets {
			setFraction(newValue, for: role, in: target)
		}
	}
	
	func fractionBinding(_ role: ChannelRole) -> Binding<Double> {
		Binding { fraction(role) } set: { setFraction($0, for: role) }
	}
	
	var dims: Bool { targets.contains { $0.profile.dims } }
	
	var mixesColor: Bool { targets.contains { $0.profile.mixesColor } }
	
	var movesHead: Bool { targets.contains { $0.profile.movesHead } }
	
	private func brightness(of target: Target) -> Double {
		switch target.profile.dimming {
		case .channel:
			fraction(.intensity, in: target)
		case let .band(channel, from, to, _):
			switch value(of: channel, in: target) {
			case ..<from: 0
			case from...to: Double(value(of: channel, in: target) - from) / Double(max(1, to - from))
			default: 1
			}
		case let .emitters(channels):
			Double(channels.map { value(of: $0, in: target) }.max() ?? 0) / 255
		case .none:
			0
		}
	}
	
	private func setBrightness(_ level: Double, of target: Target) {
		switch target.profile.dimming {
		case .channel:
			setFraction(level, for: .intensity, in: target)
		case let .band(channel, from, to, open):
			if level <= 0 {
				set(0, of: channel, in: target)
			} else if level >= 1, let open {
				set(open, of: channel, in: target)
			} else {
				set(from + UInt8((Double(to - from) * level).rounded()), of: channel, in: target)
			}
		case let .emitters(channels):
			let current = channels.map { Double(value(of: $0, in: target)) }
			let peak = current.max() ?? 0
			let goal = level * 255
			
			if peak == 0 {
				for channel in channels {
					set(UInt8(goal.rounded()), of: channel, in: target)
				}
			} else {
				for (channel, existing) in zip(channels, current) {
					set(UInt8(min(max((existing * goal / peak).rounded(), 0), 255)), of: channel, in: target)
				}
			}
		case .none:
			break
		}
	}
	
	var brightness: Double {
		get {
			var total = 0.0
			var count = 0
			
			for target in targets where target.profile.dims {
				total += brightness(of: target)
				count += 1
			}
			
			guard count > 0 else { return 0 }
			return total / Double(count)
		}
		nonmutating set {
			let level = min(max(newValue, 0), 1)
			
			for target in targets where target.profile.dims {
				setBrightness(level, of: target)
			}
		}
	}
	
	var isOn: Bool {
		guard dims else { return true }
		return brightness > 0
	}
	
	func toggleOn() {
		if brightness > 0 {
			brightness = 0
		} else {
			brightness = 1
		}
	}
	
	var brightnessBinding: Binding<Double> {
		Binding { brightness } set: { brightness = $0 }
	}
	
	var dimmers: [Console.Dimmer] {
		var found: [Console.Dimmer] = []
		
		for target in targets {
			switch target.profile.dimming {
			case let .channel(channel):
				if let address = target.start.offset(by: channel.offset - 1) {
					found.append(Console.Dimmer(address: address, kind: .linear))
				}
			case let .band(channel, from, to, open):
				if let address = target.start.offset(by: channel.offset - 1) {
					found.append(Console.Dimmer(address: address, kind: .band(from: from, to: to, open: open)))
				}
			case let .emitters(channels):
				for channel in channels {
					if let address = target.start.offset(by: channel.offset - 1) {
						found.append(Console.Dimmer(address: address, kind: .linear))
					}
				}
			case .none:
				break
			}
		}
		
		return found
	}
	
	private func mix(of target: Target) -> EmitterMix {
		var mix = EmitterMix()
		
		for channel in target.profile.emitterChannels {
			mix[channel.role] = Double(value(of: channel, in: target)) / 255
		}
		
		return mix
	}
	
	private func apply(_ recipe: EmitterMix, to target: Target) {
		let peak = target.profile.emitterChannels
			.map { Double(value(of: $0, in: target)) / 255 }
			.max() ?? 0
		let level = peak > 0 ? peak : 1
		let normalised = recipe.normalised
		
		for channel in target.profile.emitterChannels {
			set(UInt8(min(max((normalised[channel.role] * level * 255).rounded(), 0), 255)), of: channel, in: target)
		}
	}
	
	var light: LightColor {
		guard let target = targets.first(where: { $0.profile.mixesColor }) else { return .black }
		return mix(of: target).light.normalised
	}
	
	var displayColor: Color {
		guard let first = targets.first else { return .accentColor }
		return mix(of: first).light.color
	}
	
	var displayInk: Color {
		guard let first = targets.first else { return .white }
		return mix(of: first).light.contrastingInk
	}
	
	func apply(_ light: LightColor) {
		for target in targets where target.profile.mixesColor {
			apply(.mixing(light, with: target.profile.emitterChannels.map(\.role)), to: target)
		}
	}
	
	func apply(_ preset: ColorPreset) {
		for target in targets where target.profile.mixesColor {
			apply(preset.mix(with: target.profile.emitterChannels.map(\.role)), to: target)
		}
	}
	
	func apply(kelvin: Double) {
		for target in targets where target.profile.mixesColor {
			apply(.white(kelvin: kelvin, with: target.profile.emitterChannels.map(\.role)), to: target)
		}
	}
	
	var colorBinding: Binding<Color> {
		Binding { light.color } set: { apply(LightColor($0)) }
	}
	
	var kelvin: Double {
		ColorTemperature.nearest(to: light) ?? ColorTemperature.neutral
	}
	
	var emitters: [ChannelRole] {
		var roles: [ChannelRole] = []
		
		for role in Emitter.mixingOrder + [.uv] where targets.contains(where: { $0.profile.channel(role) != nil }) {
			roles.append(role)
		}
		
		return roles
	}
	
	var presets: [ColorPreset] { ColorPreset.all(for: emitters) }
	
	var emitterChannels: [ProfileChannel] { profile?.emitterChannels ?? [] }
	
	private func macro(of target: Target) -> ProfileChannel? {
		target.profile.channel(.colorMacro) ?? target.profile.channel(.colorWheel)
	}
	
	func releaseBand(of channel: ProfileChannel) -> ChannelRange? {
		if let declared = channel.ranges.first(where: \.releasesMix) { return declared }
		return channel.ranges.min { $0.from < $1.from }
	}
	
	var macroOverridesMix: Bool {
		for target in targets where target.profile.mixesColor {
			guard let macro = macro(of: target), let release = releaseBand(of: macro) else { continue }
			if !release.contains(value(of: macro, in: target)) { return true }
		}
		
		return false
	}
	
	func releaseMix() {
		for target in targets {
			guard let macro = macro(of: target), let release = releaseBand(of: macro) else { continue }
			set(release.midpoint, of: macro, in: target)
		}
	}
	
	var settings: [ProfileChannel] {
		guard let profile, let first = targets.first else { return [] }
		var shown: Set<Int> = []
		
		for channel in profile.emitterChannels where profile.mixesColor {
			shown.insert(channel.offset)
		}
		
		if profile.mixesColor, let macro = macro(of: first) {
			shown.insert(macro.offset)
		}
		
		for role in [ChannelRole.pan, .tilt, .movementSpeed] where profile.movesHead {
			if let channel = profile.channel(role) {
				shown.insert(channel.offset)
			}
			if let fine = profile.channel(role, fine: true) {
				shown.insert(fine.offset)
			}
		}
		
		switch profile.dimming {
		case let .channel(channel): shown.insert(channel.offset)
		case let .emitters(channels): for channel in channels { shown.insert(channel.offset) }
		case .band, .none: break
		}
		
		return profile.channels.filter { !shown.contains($0.offset) && !$0.isFine }
	}
	
	func applyDefaults() {
		for target in targets {
			console.set(target.profile.defaults, at: target.start)
		}
	}
	
	func centre() {
		setFraction(0.5, for: .pan)
		setFraction(0.5, for: .tilt)
	}
	
	func home() {
		applyDefaults()
		centre()
		
		for target in targets where target.profile.mixesColor {
			apply(.white(kelvin: ColorTemperature.neutral, with: target.profile.emitterChannels.map(\.role)), to: target)
		}
		
		for target in targets where target.profile.dims {
			setBrightness(1, of: target)
		}
	}
	
	var parameters: [FixtureParameter] {
		guard let profile else { return [] }
		var parameters: [FixtureParameter] = []
		
		for channel in profile.channels where !channel.isFine {
			parameters.append(FixtureParameter(coarse: channel, fine: profile.channel(channel.role, fine: true)))
		}
		
		return parameters
	}
	
	func rawValue(of parameter: FixtureParameter) -> Int {
		let high = Int(value(of: parameter.coarse))
		guard let fine = parameter.fine else { return high }
		return high * 256 + Int(value(of: fine))
	}
	
	func setRawValue(_ newValue: Int, of parameter: FixtureParameter) {
		let clamped = min(max(newValue, 0), parameter.maximum)
		
		guard let fine = parameter.fine else {
			set(UInt8(clamped), of: parameter.coarse)
			return
		}
		
		set(UInt8(clamped >> 8), of: parameter.coarse)
		set(UInt8(clamped & 0xFF), of: fine)
	}
	
	func percent(of parameter: FixtureParameter) -> Double {
		Double(rawValue(of: parameter)) / Double(parameter.maximum)
	}
	
	func band(of parameter: FixtureParameter) -> ChannelRange? {
		parameter.coarse.range(containing: value(of: parameter.coarse))
	}
	
	func channelLabel(of parameter: FixtureParameter) -> String {
		guard isSingle, let first = targets.first, let coarse = first.start.offset(by: parameter.coarse.offset - 1) else {
			return "CH \(parameter.coarse.offset)"
		}
		guard let fine = parameter.fine, let second = first.start.offset(by: fine.offset - 1) else {
			return "DMX \(coarse.value)"
		}
		return "DMX \(coarse.value)+\(second.value)"
	}
}
