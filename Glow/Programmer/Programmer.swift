import SwiftUI

@MainActor
struct Programmer {
	nonisolated struct Target: Equatable, Sendable {
		let profile: FixtureProfile
		let start: DMXAddress
		var invertsPan = false
		var invertsTilt = false
		
		func inverts(_ role: ChannelRole) -> Bool {
			switch role {
			case .pan: invertsPan
			case .tilt: invertsTilt
			default: false
			}
		}
	}
	
	let targets: [Target]
	let title: String
	let console: Console
	
	init(profile: FixtureProfile, start: DMXAddress, console: Console) {
		targets = [Target(profile: profile, start: start, invertsPan: profile.invertsPan, invertsTilt: profile.invertsTilt)]
		title = profile.model
		self.console = console
	}
	
	init?(fixture: Fixture, library: FixtureLibrary, console: Console) {
		guard let profile = library.profile(fixture.profileID) else { return nil }
		targets = [Target(profile: profile, start: fixture.start, invertsPan: fixture.invertsPan, invertsTilt: fixture.invertsTilt)]
		title = fixture.name
		self.console = console
	}
	
	init(fixtures: [Fixture], library: FixtureLibrary, console: Console) {
		targets = fixtures.compactMap { fixture in
			guard let profile = library.profile(fixture.profileID) else { return nil }
			return Target(profile: profile, start: fixture.start, invertsPan: fixture.invertsPan, invertsTilt: fixture.invertsTilt)
		}
		title = fixtures.count == 1 ? fixtures[0].name : "\(fixtures.count) Lights"
		self.console = console
	}
	
	var profile: FixtureProfile? {
		guard let first = targets.first, targets.allSatisfy({ $0.profile.id == first.profile.id }) else { return nil }
		return first.profile
	}
	
	var symbol: String { profile?.symbol ?? "lightbulb.2" }
	
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
	
	func send(_ range: ChannelRange, channel: ProfileChannel) async {
		set(range.midpoint, of: channel)
		guard let seconds = range.holdSeconds, seconds > 0 else { return }
		try? await Task.sleep(for: .seconds(seconds))
		for target in targets where value(of: channel, in: target) == range.midpoint {
			set(channel.defaultValue, of: channel, in: target)
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
		var raw = high / 255
		
		if let fine = target.profile.channel(role, fine: true) {
			raw = (high * 256 + Double(value(of: fine, in: target))) / 65535
		}
		
		return target.inverts(role) ? 1 - raw : raw
	}
	
	private func setFraction(_ newValue: Double, for role: ChannelRole, in target: Target) {
		guard let coarse = target.profile.channel(role) else { return }
		let wanted = min(max(newValue, 0), 1)
		let clamped = target.inverts(role) ? 1 - wanted : wanted
		
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
				let white = EmitterMix.mixing(LightColor(red: 1, green: 1, blue: 1), emitters: target.profile.emitters, mixing: .additive)
				for channel in channels {
					setFraction(white[channel.role] * level, for: channel.role, in: target)
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
	
	var dimmers: [Dimmer] {
		var found: [Dimmer] = []
		
		for target in targets {
			switch target.profile.dimming {
			case let .channel(channel):
				if let address = target.start.offset(by: channel.offset - 1) {
					let fine = target.profile.parameters.first { $0.coarse.offset == channel.offset }?.fine
					found.append(Dimmer(address: address, kind: .linear, fineAddress: fine.flatMap { target.start.offset(by: $0.offset - 1) }))
				}
			case let .band(channel, from, to, open):
				if let address = target.start.offset(by: channel.offset - 1) {
					found.append(Dimmer(address: address, kind: .band(from: from, to: to, open: open)))
				}
			case let .emitters(channels):
				for channel in channels {
					if let address = target.start.offset(by: channel.offset - 1) {
						let fine = target.profile.parameters.first { $0.coarse.offset == channel.offset }?.fine
							found.append(Dimmer(address: address, kind: .linear, fineAddress: fine.flatMap { target.start.offset(by: $0.offset - 1) }))
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
			mix[channel.role] = fraction(channel.role, in: target)
		}
		
		return mix
	}
	
	private func apply(_ recipe: EmitterMix, to target: Target) {
		guard target.profile.mixing == .additive else {
			for channel in target.profile.emitterChannels {
				setFraction(recipe[channel.role], for: channel.role, in: target)
			}
			return
		}
		
		let peak = target.profile.emitterChannels
			.map { Double(value(of: $0, in: target)) / 255 }
			.max() ?? 0
		let level = peak > 0 ? peak : 1
		let normalised = recipe.normalised
		
		for channel in target.profile.emitterChannels {
			setFraction(normalised[channel.role] * level, for: channel.role, in: target)
		}
	}
	
	var light: LightColor {
		guard let target = targets.first(where: { $0.profile.mixesColor }) else { return .black }
		return mix(of: target).light(target.profile.mixing).normalised
	}
	
	var displayInk: Color {
		guard mixesColor else { return .black }
		return light.contrastingInk
	}
	
	var glow: Color {
		guard mixesColor else { return .white }
		return light.color
	}
	
	func apply(_ light: LightColor) {
		for target in targets where target.profile.mixesColor {
			apply(.mixing(light, emitters: target.profile.emitters, mixing: target.profile.mixing), to: target)
		}
	}
	
	func apply(_ preset: ColorPreset) {
		for target in targets where target.profile.mixesColor {
			apply(preset.mix(emitters: target.profile.emitters, mixing: target.profile.mixing), to: target)
		}
	}
	
	func apply(kelvin: Double) {
		for target in targets where target.profile.mixesColor {
			apply(.white(kelvin: kelvin, emitters: target.profile.emitters, mixing: target.profile.mixing), to: target)
		}
	}
	
	var colorBinding: Binding<Color> {
		Binding { light.color } set: { apply(LightColor($0)) }
	}
	
	var kelvin: Double {
		ColorTemperature.nearest(to: light) ?? ColorTemperature.neutral
	}
	
	var selectedPresetID: String? {
		guard !macroOverridesMix, let target = targets.first(where: { $0.profile.mixesColor }) else { return nil }
		guard target.profile.emitterChannels.contains(where: { value(of: $0, in: target) != $0.defaultValue }) else { return nil }
		var selected: String?
		var closest = 0.025
		
		for preset in presets {
			let distance = preset.mix(emitters: target.profile.emitters, mixing: target.profile.mixing).light(target.profile.mixing).normalised.distance(to: light)
			if distance < closest {
				closest = distance
				selected = preset.id
			}
		}
		
		return selected
	}
	
	var emitters: [ChannelRole] {
		var roles: [ChannelRole] = []
		
		for role in Emitter.mixingOrder + [.uv] where targets.contains(where: { $0.profile.channel(role) != nil }) {
			roles.append(role)
		}
		
		return roles
	}
	
	var presets: [ColorPreset] { ColorPreset.all(emitters: emitters) }
	
	var emitterChannels: [ProfileChannel] { profile?.emitterChannels ?? [] }
	
	var isSubtractive: Bool { targets.contains { $0.profile.mixing == .subtractive } }
	
	func guardedBinding(_ parameter: FixtureParameter) -> Binding<Double> {
		Binding { Double(rawValue(of: parameter)) } set: { setRawValue(stepping(whole($0, of: parameter), of: parameter), of: parameter) }
	}
	
	private func whole(_ value: Double, of parameter: FixtureParameter) -> Int {
		guard value > 0 else { return 0 }
		return value < Double(parameter.maximum) ? Int(value.rounded()) : parameter.maximum
	}
	
	private func stepping(_ value: Int, of parameter: FixtureParameter) -> Int {
		guard parameter.fine == nil, (0...255).contains(value) else { return value }
		guard let blocked = parameter.ranges.first(where: { $0.requiresConfirmation && $0.contains(UInt8(value)) }) else { return value }
		guard blocked.from > 0 else { return Int(blocked.to) + 1 }
		return Int(blocked.from) - 1
	}
	
	var balancesWhite: Bool {
		guard let profile, profile.mixing == .additive else { return false }
		return profile.channel(.white) != nil || profile.channel(.amber) != nil
	}
	
	private func macro(of target: Target) -> ProfileChannel? {
		target.profile.channel(.colorMacro) ?? target.profile.channel(.colorWheel)
	}
	
	func releaseBand(of channel: ProfileChannel) -> ChannelRange? {
		if let declared = channel.ranges.first(where: \.releasesMix) { return declared }
		return channel.ranges.min { $0.from < $1.from }
	}
	
	var macroChannel: ProfileChannel? {
		profile?.channel(.colorMacro) ?? profile?.channel(.colorWheel)
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
		guard let profile else { return [] }
		var shown: Set<Int> = []
		
		for channel in profile.emitterChannels where profile.mixesColor {
			shown.insert(channel.offset)
		}
		
		if profile.mixesColor, let macro = macroChannel {
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
	
	var parameters: [FixtureParameter] { profile?.parameters ?? [] }
	
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
	
	func rawBinding(_ parameter: FixtureParameter) -> Binding<Double> {
		Binding { Double(rawValue(of: parameter)) } set: { setRawValue(whole($0, of: parameter), of: parameter) }
	}
	
	func percent(of parameter: FixtureParameter) -> Double {
		Double(rawValue(of: parameter)) / Double(parameter.maximum)
	}
	
	func band(of parameter: FixtureParameter) -> ChannelRange? {
		parameter.coarse.range(containing: value(of: parameter.coarse))
	}
	
	func bandLabel(of parameter: FixtureParameter) -> String {
		band(of: parameter)?.label ?? parameter.role.name
	}
	
	func channelLabel(of parameter: FixtureParameter) -> String {
		guard targets.count == 1, let first = targets.first, let coarse = first.start.offset(by: parameter.coarse.offset - 1) else {
			return "CH \(parameter.coarse.offset)"
		}
		guard let fine = parameter.fine, let second = first.start.offset(by: fine.offset - 1) else {
			return "DMX \(coarse.value)"
		}
		return "DMX \(coarse.value)+\(second.value)"
	}
}
