import SwiftUI

@MainActor
struct Programmer {
	nonisolated struct Target: Equatable, Sendable {
		let mode: FixtureMode
		let start: DMXAddress
		var invertsPan = false
		var invertsTilt = false
		
		func inverts(_ attribute: Attribute) -> Bool {
			switch attribute {
			case .pan: invertsPan
			case .tilt: invertsTilt
			default: false
			}
		}
		
		var span: ClosedRange<Int> {
			start.value...(start.value + max(1, mode.channelCount) - 1)
		}
	}
	
	let targets: [Target]
	let title: String
	let console: Console
	
	init(mode: FixtureMode, start: DMXAddress, console: Console) {
		targets = [Target(mode: mode, start: start, invertsPan: mode.invertsPan, invertsTilt: mode.invertsTilt)]
		title = mode.model
		self.console = console
	}
	
	init?(fixture: Fixture, library: FixtureLibrary, console: Console) {
		guard let mode = library.mode(fixture.typeID) else { return nil }
		targets = [Target(mode: mode, start: fixture.start, invertsPan: fixture.invertsPan, invertsTilt: fixture.invertsTilt)]
		title = fixture.name
		self.console = console
	}
	
	init(fixtures: [Fixture], library: FixtureLibrary, console: Console) {
		targets = fixtures.compactMap { fixture in
			guard let mode = library.mode(fixture.typeID) else { return nil }
			return Target(mode: mode, start: fixture.start, invertsPan: fixture.invertsPan, invertsTilt: fixture.invertsTilt)
		}
		title = fixtures.count == 1 ? fixtures[0].name : "\(fixtures.count) Lights"
		self.console = console
	}
	
	var mode: FixtureMode? {
		guard let first = targets.first, targets.allSatisfy({ $0.mode.id == first.mode.id }) else { return nil }
		return first.mode
	}
	
	var symbol: String { mode?.symbol ?? "lightbulb.2" }
	
	private func address(_ offset: Int, in target: Target) -> DMXAddress? {
		target.start.offset(by: offset - 1)
	}
	
	private func value(of channel: FixtureChannel, in target: Target) -> UInt8 {
		guard let address = address(channel.offset, in: target) else { return 0 }
		return console.value(at: address)
	}
	
	private func set(_ value: UInt8, of channel: FixtureChannel, in target: Target) {
		guard let address = address(channel.offset, in: target) else { return }
		console.set(value, at: address)
	}
	
	private func raw(of channel: FixtureChannel, in target: Target) -> Int {
		let high = Int(value(of: channel, in: target))
		guard let fine = channel.fineOffset, let address = address(fine, in: target) else { return high }
		return high * 256 + Int(console.value(at: address))
	}
	
	private func setRaw(_ newValue: Int, of channel: FixtureChannel, in target: Target) {
		let clamped = min(max(newValue, 0), channel.maximum)
		
		guard let fine = channel.fineOffset, let address = address(fine, in: target) else {
			set(UInt8(clamped), of: channel, in: target)
			return
		}
		
		set(UInt8(clamped >> 8), of: channel, in: target)
		console.set(UInt8(clamped & 0xFF), at: address)
	}
	
	func value(of channel: FixtureChannel) -> UInt8 {
		guard let first = targets.first else { return 0 }
		return value(of: channel, in: first)
	}
	
	func set(_ value: UInt8, of channel: FixtureChannel) {
		for target in targets {
			set(value, of: channel, in: target)
		}
	}
	
	func isActive(_ channel: FixtureChannel) -> Bool {
		for target in targets {
			guard let address = address(channel.offset, in: target) else { continue }
			if console.isActive(address) { return true }
		}
		
		return false
	}
	
	func isActive(_ group: FeatureGroup) -> Bool {
		for target in targets {
			for channel in target.mode.channels(in: group) where isActive(channel) { return true }
		}
		
		return false
	}
	
	func send(_ range: ChannelFunction, channel: FixtureChannel) async {
		set(range.midpoint, of: channel)
		guard let seconds = range.holdSeconds, seconds > 0 else { return }
		try? await Task.sleep(for: .seconds(seconds))
		
		for target in targets where value(of: channel, in: target) == range.midpoint {
			set(channel.defaultValue, of: channel, in: target)
			console.release(target.span, only: channel.offset)
		}
	}
	
	func send(_ set: ChannelSet, channel: FixtureChannel) {
		self.set(set.midpoint, of: channel)
	}
	
	func fractionBinding(of channel: FixtureChannel) -> Binding<Double> {
		Binding { Double(rawValue(of: channel)) / Double(channel.maximum) } set: { setRawValue(Int(($0 * Double(channel.maximum)).rounded()), of: channel) }
	}
	
	func binding(_ channel: FixtureChannel) -> Binding<Double> {
		Binding { Double(value(of: channel)) } set: { set(UInt8(min(max($0.rounded(), 0), 255)), of: channel) }
	}
	
	func band(of channel: FixtureChannel) -> ChannelFunction? {
		channel.function(containing: value(of: channel))
	}
	
	func slot(of channel: FixtureChannel) -> ChannelSet? {
		band(of: channel)?.set(containing: value(of: channel))
	}
	
	func bands(of channel: FixtureChannel) -> [ChannelFunction] {
		guard case let .band(dimmer, from, to, _) = mode?.dimming, dimmer.offset == channel.offset else { return channel.functions }
		return channel.functions.filter { $0.from != from || $0.to != to }
	}
	
	func adjustableBand(of channel: FixtureChannel) -> ChannelFunction? {
		guard let active = band(of: channel), active.kind == .proportional, bands(of: channel).contains(active) else { return nil }
		return active
	}
	
	private func fraction(_ attribute: Attribute, in target: Target) -> Double {
		guard let channel = target.mode.channel(attribute) else { return 0 }
		let raw = Double(self.raw(of: channel, in: target)) / Double(channel.maximum)
		return target.inverts(attribute) ? 1 - raw : raw
	}
	
	private func setFraction(_ newValue: Double, for attribute: Attribute, in target: Target) {
		guard let channel = target.mode.channel(attribute) else { return }
		let wanted = min(max(newValue, 0), 1)
		let clamped = target.inverts(attribute) ? 1 - wanted : wanted
		setRaw(Int((clamped * Double(channel.maximum)).rounded()), of: channel, in: target)
	}
	
	func fraction(_ attribute: Attribute) -> Double {
		for target in targets where target.mode.channel(attribute) != nil {
			return fraction(attribute, in: target)
		}
		
		return 0
	}
	
	func setFraction(_ newValue: Double, for attribute: Attribute) {
		for target in targets {
			setFraction(newValue, for: attribute, in: target)
		}
	}
	
	func fractionBinding(_ attribute: Attribute) -> Binding<Double> {
		Binding { fraction(attribute) } set: { setFraction($0, for: attribute) }
	}
	
	var dims: Bool { targets.contains { $0.mode.dims } }
	
	var mixesColor: Bool { targets.contains { $0.mode.mixesColor } }
	
	var movesHead: Bool { targets.contains { $0.mode.movesHead } }
	
	private func brightness(of target: Target) -> Double {
		switch target.mode.dimming {
		case .channel:
			fraction(.dimmer, in: target)
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
		switch target.mode.dimming {
		case .channel:
			setFraction(level, for: .dimmer, in: target)
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
			let defaults = channels.map { Double($0.defaultValue) }
			var hue = current.max() ?? 0 > 0 ? current : defaults
			
			if hue.max() ?? 0 == 0 {
				let white = EmitterMix.mixing(LightColor(red: 1, green: 1, blue: 1), emitters: target.mode.emitters, mixing: .additive)
				hue = channels.map { white[$0.attribute] }
			}
			
			let reference = hue.max() ?? 0
			guard reference > 0 else { return }
			
			for (channel, share) in zip(channels, hue) {
				set(UInt8(min(max((share * level * 255 / reference).rounded(), 0), 255)), of: channel, in: target)
			}
		case .none:
			break
		}
	}
	
	var brightness: Double {
		get {
			var total = 0.0
			var count = 0
			
			for target in targets where target.mode.dims {
				total += brightness(of: target)
				count += 1
			}
			
			guard count > 0 else { return 0 }
			return total / Double(count)
		}
		nonmutating set {
			let level = min(max(newValue, 0), 1)
			
			for target in targets where target.mode.dims {
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
			switch target.mode.dimming {
			case let .channel(channel):
				if let coarse = address(channel.offset, in: target) {
					found.append(Dimmer(address: coarse, kind: .linear, fineAddress: channel.fineOffset.flatMap { address($0, in: target) }))
				}
			case let .band(channel, from, to, open):
				if let coarse = address(channel.offset, in: target) {
					found.append(Dimmer(address: coarse, kind: .band(from: from, to: to, open: open)))
				}
			case let .emitters(channels):
				for channel in channels {
					if let coarse = address(channel.offset, in: target) {
						found.append(Dimmer(address: coarse, kind: .linear, fineAddress: channel.fineOffset.flatMap { address($0, in: target) }))
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
		
		for channel in target.mode.emitterChannels {
			mix[channel.attribute] = fraction(channel.attribute, in: target)
		}
		
		return mix
	}
	
	private func apply(_ recipe: EmitterMix, to target: Target) {
		guard target.mode.mixing == .additive else {
			for channel in target.mode.emitterChannels {
				setFraction(recipe[channel.attribute], for: channel.attribute, in: target)
			}
			return
		}
		
		let peak = target.mode.emitterChannels
			.map { Double(value(of: $0, in: target)) / 255 }
			.max() ?? 0
		let level = peak > 0 ? peak : 1
		let normalised = recipe.normalised
		
		for channel in target.mode.emitterChannels {
			setFraction(normalised[channel.attribute] * level, for: channel.attribute, in: target)
		}
	}
	
	var light: LightColor {
		guard let target = targets.first(where: { $0.mode.mixesColor }) else { return .black }
		return mix(of: target).light(target.mode.mixing).normalised
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
		for target in targets where target.mode.mixesColor {
			apply(.mixing(light, emitters: target.mode.emitters, mixing: target.mode.mixing), to: target)
		}
	}
	
	func apply(_ preset: ColorPreset) {
		for target in targets where target.mode.mixesColor {
			apply(preset.mix(emitters: target.mode.emitters, mixing: target.mode.mixing), to: target)
		}
	}
	
	func apply(kelvin: Double) {
		for target in targets where target.mode.mixesColor {
			apply(.white(kelvin: kelvin, emitters: target.mode.emitters, mixing: target.mode.mixing), to: target)
		}
	}
	
	var lightBinding: Binding<LightColor> {
		Binding { light } set: { apply($0) }
	}
	
	var kelvin: Double {
		ColorTemperature.nearest(to: light) ?? ColorTemperature.neutral
	}
	
	var selectedPresetID: String? {
		guard !macroOverridesMix, let target = targets.first(where: { $0.mode.mixesColor }) else { return nil }
		guard target.mode.emitterChannels.contains(where: { isActive($0) }) else { return nil }
		var selected: String?
		var closest = 0.025
		
		for preset in presets {
			let distance = preset.mix(emitters: target.mode.emitters, mixing: target.mode.mixing).light(target.mode.mixing).normalised.distance(to: light)
			if distance < closest {
				closest = distance
				selected = preset.id
			}
		}
		
		return selected
	}
	
	var emitters: [Attribute] {
		var roles: [Attribute] = []
		
		for attribute in Emitter.mixingOrder + [.uv] where targets.contains(where: { $0.mode.channel(attribute) != nil }) {
			roles.append(attribute)
		}
		
		return roles
	}
	
	var presets: [ColorPreset] { ColorPreset.all(emitters: emitters) }
	
	var emitterChannels: [FixtureChannel] { mode?.emitterChannels ?? [] }
	
	var isSubtractive: Bool { targets.contains { $0.mode.mixing == .subtractive } }
	
	func guardedBinding(_ channel: FixtureChannel) -> Binding<Double> {
		Binding { Double(rawValue(of: channel)) } set: { setRawValue(stepping(whole($0, of: channel), of: channel), of: channel) }
	}
	
	private func whole(_ value: Double, of channel: FixtureChannel) -> Int {
		guard value > 0 else { return 0 }
		return value < Double(channel.maximum) ? Int(value.rounded()) : channel.maximum
	}
	
	private func stepping(_ value: Int, of channel: FixtureChannel) -> Int {
		guard !channel.isWide, (0...255).contains(value) else { return value }
		guard let blocked = channel.functions.first(where: { $0.requiresConfirmation && $0.contains(UInt8(value)) }) else { return value }
		guard blocked.from > 0 else { return Int(blocked.to) + 1 }
		return Int(blocked.from) - 1
	}
	
	var balancesWhite: Bool {
		guard let mode, mode.mixing == .additive else { return false }
		return mode.channel(.white) != nil || mode.channel(.amber) != nil
	}
	
	private func macro(of target: Target) -> FixtureChannel? {
		target.mode.channel(.colorMacro) ?? target.mode.channel(.colorWheel)
	}
	
	func releaseBand(of channel: FixtureChannel) -> ChannelFunction? {
		channel.functions.first { $0.purpose == .release }
	}
	
	var macroChannel: FixtureChannel? {
		mode?.channel(.colorMacro) ?? mode?.channel(.colorWheel)
	}
	
	var macroOverridesMix: Bool {
		for target in targets where target.mode.mixesColor {
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
	
	func settings(in group: FeatureGroup) -> [FixtureChannel] {
		guard let mode else { return [] }
		var shown: Set<Int> = []
		
		if mode.mixesColor {
			for channel in mode.emitterChannels {
				shown.insert(channel.offset)
			}
			
			if let macro = macroChannel {
				shown.insert(macro.offset)
			}
		}
		
		if mode.movesHead {
			for attribute in [Attribute.pan, .tilt, .panTiltSpeed] {
				if let channel = mode.channel(attribute) {
					shown.insert(channel.offset)
				}
			}
		}
		
		switch mode.dimming {
		case let .channel(channel): shown.insert(channel.offset)
		case let .emitters(channels): for channel in channels { shown.insert(channel.offset) }
		case .band, .none: break
		}
		
		return mode.channels(in: group).filter { !shown.contains($0.offset) }
	}
	
	var settings: [FixtureChannel] {
		FeatureGroup.allCases.flatMap { settings(in: $0) }
	}
	
	func release(_ group: FeatureGroup) {
		for target in targets {
			for channel in target.mode.channels(in: group) {
				setRaw(channel.neutral, of: channel, in: target)
				console.release(target.span, only: channel.offset)
				
				if let fine = channel.fineOffset {
					console.release(target.span, only: fine)
				}
			}
		}
	}
	
	var groups: [FeatureGroup] {
		FeatureGroup.allCases.filter { group in targets.contains { !$0.mode.channels(in: group).isEmpty } }
	}
	
	func channels(in group: FeatureGroup) -> [FixtureChannel] {
		mode?.channels(in: group) ?? []
	}
	
	func channel(_ attribute: Attribute) -> FixtureChannel? {
		mode?.channel(attribute)
	}
	
	func isEnabled(_ channel: FixtureChannel) -> Bool {
		guard let dependency = channel.enabledBy else { return true }
		
		for target in targets {
			guard let address = address(dependency.offset, in: target) else { continue }
			if !dependency.contains(console.value(at: address)) { return false }
		}
		
		return true
	}
	
	func blocker(of channel: FixtureChannel) -> FixtureChannel? {
		guard let dependency = channel.enabledBy, !isEnabled(channel) else { return nil }
		return mode?.channels.first { $0.offset == dependency.offset }
	}
	
	var shutterChannel: FixtureChannel? {
		guard case let .band(channel, _, _, _) = mode?.dimming else { return mode?.channel(.shutter) }
		return channel
	}
	
	var strobeFunction: ChannelFunction? {
		guard let channel = shutterChannel else { return nil }
		guard let active = band(of: channel), active.purpose == nil, active.kind == .proportional else { return nil }
		return active
	}
	
	var strobeHertz: Double? {
		guard let channel = shutterChannel, let function = strobeFunction, function.unit == .hertz else { return nil }
		guard let from = function.physicalFrom, let to = function.physicalTo, function.to > function.from else { return nil }
		let share = Double(value(of: channel) - function.from) / Double(function.to - function.from)
		return from + (to - from) * share
	}
	
	func physical(of channel: FixtureChannel) -> String? {
		band(of: channel)?.physical(at: value(of: channel))
	}
	
	func degrees(_ attribute: Attribute) -> Double? {
		guard let channel = mode?.channel(attribute), let function = channel.functions.first, function.unit == .degrees else { return nil }
		guard let from = function.physicalFrom, let to = function.physicalTo else { return nil }
		return from + (to - from) * fraction(attribute)
	}
	
	func applyDefaults() {
		for target in targets {
			console.set(target.mode.defaults, at: target.start)
			console.release(target.span)
		}
	}
	
	func highlight() {
		for target in targets {
			for channel in target.mode.channels {
				guard let value = channel.highlight else { continue }
				set(value, of: channel, in: target)
			}
			
			if target.mode.movesHead {
				setFraction(0.5, for: .pan, in: target)
				setFraction(0.5, for: .tilt, in: target)
			}
			
			console.release(target.span)
		}
	}
	
	func centre() {
		setFraction(0.5, for: .pan)
		setFraction(0.5, for: .tilt)
	}
	
	var channels: [FixtureChannel] { mode?.channels ?? [] }
	
	func rawValue(of channel: FixtureChannel) -> Int {
		guard let first = targets.first else { return 0 }
		return raw(of: channel, in: first)
	}
	
	func setRawValue(_ newValue: Int, of channel: FixtureChannel) {
		for target in targets {
			setRaw(newValue, of: channel, in: target)
		}
	}
	
	func rawBinding(_ channel: FixtureChannel) -> Binding<Double> {
		Binding { Double(rawValue(of: channel)) } set: { setRawValue(whole($0, of: channel), of: channel) }
	}
	
	func percent(of channel: FixtureChannel) -> Double {
		Double(rawValue(of: channel)) / Double(channel.maximum)
	}
	
	func bandLabel(of channel: FixtureChannel) -> String {
		slot(of: channel)?.label ?? band(of: channel)?.label ?? channel.attribute.name
	}
	
	func channelLabel(of channel: FixtureChannel) -> String {
		guard targets.count == 1, let first = targets.first, let coarse = address(channel.offset, in: first) else {
			return "CH \(channel.offset)"
		}
		guard let fine = channel.fineOffset, let second = address(fine, in: first) else {
			return "DMX \(coarse.value)"
		}
		return "DMX \(coarse.value)+\(second.value)"
	}
}
