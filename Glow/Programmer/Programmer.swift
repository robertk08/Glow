import SwiftUI

@MainActor
struct Programmer {
	nonisolated struct Target: Equatable, Sendable {
		let type: FixtureType
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
			start.value...(start.value + max(1, type.channelCount) - 1)
		}
	}
	
	let targets: [Target]
	let title: String
	let console: Console
	let type: FixtureType?
	let channels: [FixtureChannel]
	
	init(type: FixtureType, start: DMXAddress, console: Console) {
		self.init(targets: [Target(type: type, start: start, invertsPan: type.invertsPan, invertsTilt: type.invertsTilt)], title: type.model, console: console)
	}
	
	init?(fixture: Fixture, library: FixtureLibrary, console: Console) {
		guard let type = library.type(fixture.typeID) else { return nil }
		self.init(targets: [Target(type: type, start: fixture.start, invertsPan: fixture.invertsPan, invertsTilt: fixture.invertsTilt)], title: fixture.name, console: console)
	}
	
	init(fixtures: [Fixture], library: FixtureLibrary, console: Console) {
		let targets = fixtures.compactMap { fixture -> Target? in
			guard let type = library.type(fixture.typeID) else { return nil }
			return Target(type: type, start: fixture.start, invertsPan: fixture.invertsPan, invertsTilt: fixture.invertsTilt)
		}
		self.init(targets: targets, title: fixtures.count == 1 ? fixtures[0].name : "\(fixtures.count) Lights", console: console)
	}
	
	private init(targets: [Target], title: String, console: Console) {
		self.targets = targets
		self.title = title
		self.console = console
		
		if let first = targets.first, targets.allSatisfy({ $0.type.id == first.type.id }) {
			type = first.type
			channels = first.type.channels
			return
		}
		
		type = nil
		var kinds: [FixtureType] = []
		var shared: [FixtureChannel] = []
		
		for target in targets where !kinds.contains(where: { $0.id == target.type.id }) {
			kinds.append(target.type)
		}
		
		for kind in kinds {
			for channel in kind.channels where !shared.contains(where: { $0.attribute == channel.attribute && $0.name == channel.name }) {
				if kinds.allSatisfy({ other in other.channels.allSatisfy { $0.attribute != channel.attribute || $0.name != channel.name || $0.matches(channel) } }) { shared.append(channel) }
			}
		}
		
		channels = shared
	}
	
	var symbol: String { type?.symbol ?? "lightbulb.2" }
	
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
	
	private func counterpart(of channel: FixtureChannel, in target: Target) -> FixtureChannel? {
		target.type.channels.first { $0 == channel } ?? target.type.channels.first { $0.matches(channel) }
	}
	
	func value(of channel: FixtureChannel) -> UInt8 {
		for target in targets {
			if let own = counterpart(of: channel, in: target) { return value(of: own, in: target) }
		}
		
		return 0
	}
	
	func set(_ value: UInt8, of channel: FixtureChannel) {
		for target in targets {
			if let own = counterpart(of: channel, in: target) { set(value, of: own, in: target) }
		}
	}
	
	func isActive(_ channel: FixtureChannel) -> Bool {
		for target in targets {
			guard let own = counterpart(of: channel, in: target), let address = address(own.offset, in: target) else { continue }
			if console.isActive(address) { return true }
		}
		
		return false
	}
	
	func isActive(_ group: FeatureGroup) -> Bool {
		for target in targets {
			for channel in target.type.channels(in: group) where isActive(channel) { return true }
		}
		
		return false
	}
	
	nonisolated struct Choice: Identifiable, Sendable, Equatable {
		let id: String
		let label: String
		let value: UInt8
		let swatch: [LightColor]
		let shape: GoboShape?
		let confirms: Bool
		let function: ChannelFunction
	}
	
	func modes(of channel: FixtureChannel) -> [Choice] {
		bands(of: channel).map { band in
			Choice(id: "\(band.from)-\(band.to)", label: band.label, value: band.sets.first?.midpoint ?? band.midpoint, swatch: band.swatch, shape: nil, confirms: band.requiresConfirmation, function: band)
		}
	}
	
	func slotBand(of channel: FixtureChannel) -> ChannelFunction? {
		band(of: channel).flatMap { $0.sets.isEmpty ? nil : $0 } ?? bands(of: channel).first { !$0.sets.isEmpty }
	}
	
	func slots(of channel: FixtureChannel) -> [Choice] {
		guard let band = slotBand(of: channel) else { return [] }
		
		let found = band.sets.map { slot in
			Choice(id: "\(slot.from)-\(slot.to)", label: slot.label, value: slot.midpoint, swatch: slot.swatch, shape: slot.shape, confirms: band.requiresConfirmation, function: band)
		}
		
		guard let open = channel.functions.first(where: { $0.purpose == .open }), band.sets.contains(where: { $0.shape != nil }) else { return found }
		
		return [Choice(id: "\(open.from)-\(open.to)", label: open.label, value: open.midpoint, swatch: [], shape: .open, confirms: open.requiresConfirmation, function: open)] + found
	}
	
	func isMarked(_ channel: FixtureChannel) -> Bool {
		let slots = slotBand(of: channel)?.sets ?? []
		return !slots.isEmpty && slots.allSatisfy { $0.shape != nil || !$0.colors.isEmpty }
	}
	
	var goboWheels: [FixtureChannel] {
		[channel(.gobo), channel(.gobo2)].compactMap { $0 }
	}
	
	func spinner(of wheel: FixtureChannel) -> FixtureChannel? {
		switch wheel.attribute {
		case .gobo: channel(.goboRotation)
		case .gobo2: channel(.gobo2Rotation)
		default: nil
		}
	}
	
	func draws(_ wheel: FixtureChannel) -> Bool {
		wheel.functions.contains { $0.sets.contains { $0.shape != nil } }
	}
	
	func shape(of wheel: FixtureChannel) -> GoboShape? {
		slot(of: wheel)?.shape
	}
	
	func standing(of wheel: FixtureChannel) -> String {
		slot(of: wheel)?.label ?? band(of: wheel)?.label ?? ""
	}
	
	func standingAngle(of spinner: FixtureChannel?) -> Angle {
		guard let spinner, let band = band(of: spinner), band.unit == .degrees else { return .zero }
		guard let from = band.physicalFrom, let to = band.physicalTo, band.to > band.from else { return .zero }
		let share = Double(value(of: spinner) - band.from) / Double(band.to - band.from)
		return .degrees(from + (to - from) * share)
	}
	
	func turns(of spinner: FixtureChannel?) -> Double? {
		guard let spinner, let band = band(of: spinner) else { return nil }
		guard band.kind == .proportional, band.unit == nil, band.to > band.from else { return nil }
		let share = Double(value(of: spinner) - band.from) / Double(band.to - band.from)
		return 8 + share * 52
	}
	
	func mode(of channel: FixtureChannel) -> String {
		band(of: channel).map { "\($0.from)-\($0.to)" } ?? ""
	}
	
	func selection(of channel: FixtureChannel) -> String {
		slot(of: channel).map { "\($0.from)-\($0.to)" } ?? ""
	}
	
	func choice(_ id: String, of channel: FixtureChannel) -> Choice? {
		(modes(of: channel) + slots(of: channel)).first { $0.id == id }
	}
	
	func send(_ choice: Choice, of channel: FixtureChannel) async {
		set(choice.value, of: channel)
		guard let seconds = choice.function.holdSeconds, seconds > 0 else { return }
		try? await Task.sleep(for: .seconds(seconds))
		
		for target in targets {
			guard let own = counterpart(of: channel, in: target), value(of: own, in: target) == choice.value else { continue }
			set(own.defaultValue, of: own, in: target)
			console.release(target.span, only: own.offset)
		}
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
		for target in targets {
			guard case let .band(dimmer, from, to, _) = target.type.dimming, dimmer.matches(channel) else { continue }
			return channel.functions.filter { $0.from != from || $0.to != to }
		}
		
		return channel.functions
	}
	
	nonisolated struct Scale: Sendable {
		let from: UInt8
		let to: UInt8
		let unit: PhysicalUnit
	}
	
	func scale(of channel: FixtureChannel) -> Scale? {
		let measured = bands(of: channel).filter { $0.unit != nil && $0.sets.isEmpty }.sorted { $0.from < $1.from }
		guard measured.count > 2, let unit = measured.first?.unit, measured.allSatisfy({ $0.unit == unit }) else { return nil }
		guard zip(measured, measured.dropFirst()).allSatisfy({ Int($0.to) + 1 == Int($1.from) }) else { return nil }
		return Scale(from: measured[0].from, to: measured[measured.count - 1].to, unit: unit)
	}
	
	func stops(of channel: FixtureChannel) -> [Choice] {
		bands(of: channel).filter { $0.kind == .setting }.map { band in
			Choice(id: "\(band.from)-\(band.to)", label: band.physical(at: band.midpoint) ?? band.label, value: band.midpoint, swatch: band.swatch, shape: nil, confirms: band.requiresConfirmation, function: band)
		}
	}
	
	func adjustableBand(of channel: FixtureChannel) -> ChannelFunction? {
		guard let active = band(of: channel), active.kind == .proportional, bands(of: channel).contains(active) else { return nil }
		return active
	}
	
	private func fraction(_ attribute: Attribute, in target: Target) -> Double {
		guard let channel = target.type.channel(attribute) else { return 0 }
		let raw = Double(self.raw(of: channel, in: target)) / Double(channel.maximum)
		return target.inverts(attribute) ? 1 - raw : raw
	}
	
	private func setFraction(_ newValue: Double, for attribute: Attribute, in target: Target) {
		guard let channel = target.type.channel(attribute) else { return }
		let wanted = min(max(newValue, 0), 1)
		let clamped = target.inverts(attribute) ? 1 - wanted : wanted
		setRaw(Int((clamped * Double(channel.maximum)).rounded()), of: channel, in: target)
	}
	
	func fraction(_ attribute: Attribute) -> Double {
		for target in targets where target.type.channel(attribute) != nil {
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
	
	var dims: Bool { targets.contains { $0.type.dims } }
	
	var mixesColor: Bool { targets.contains { $0.type.mixesColor } }
	
	var movesHead: Bool { targets.contains { $0.type.movesHead } }
	
	var brightness: Double {
		get {
			var total = 0.0
			var count = 0
			
			for target in targets where target.type.dims {
				count += 1
				
				switch target.type.dimming {
				case .channel:
					total += fraction(.dimmer, in: target)
				case let .band(channel, from, to, _):
					let level = value(of: channel, in: target)
					if level > to {
						total += 1
					} else if level >= from {
						total += Double(level - from) / Double(max(1, to - from))
					}
				case let .emitters(channels):
					total += Double(channels.map { value(of: $0, in: target) }.max() ?? 0) / 255
				case .none:
					break
				}
			}
			
			guard count > 0 else { return 0 }
			return total / Double(count)
		}
		nonmutating set {
			let level = min(max(newValue, 0), 1)
			
			for target in targets where target.type.dims {
				switch target.type.dimming {
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
						let white = EmitterMix.mixing(LightColor(red: 1, green: 1, blue: 1), emitters: target.type.emitters, mixing: .additive)
						hue = channels.map { white[$0.attribute] }
					}
					
					let reference = hue.max() ?? 0
					guard reference > 0 else { continue }
					
					for (channel, share) in zip(channels, hue) {
						set(UInt8(min(max((share * level * 255 / reference).rounded(), 0), 255)), of: channel, in: target)
					}
				case .none:
					break
				}
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
			switch target.type.dimming {
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
		
		for channel in target.type.emitterChannels {
			mix[channel.attribute] = fraction(channel.attribute, in: target)
		}
		
		return mix
	}
	
	private func apply(_ recipe: EmitterMix, to target: Target) {
		guard target.type.mixing == .additive else {
			for channel in target.type.emitterChannels {
				setFraction(recipe[channel.attribute], for: channel.attribute, in: target)
			}
			return
		}
		
		let peak = target.type.emitterChannels
			.map { Double(value(of: $0, in: target)) / 255 }
			.max() ?? 0
		let level = peak > 0 ? peak : 1
		let normalised = recipe.normalised
		
		for channel in target.type.emitterChannels {
			setFraction(normalised[channel.attribute] * level, for: channel.attribute, in: target)
		}
	}
	
	var light: LightColor {
		guard let target = targets.first(where: { $0.type.mixesColor }) else { return .black }
		return mix(of: target).light(target.type.mixing).normalised
	}
	
	var displayInk: Color {
		guard mixesColor else { return .black }
		return light.contrastingInk
	}
	
	var glow: Color {
		guard mixesColor else { return .white }
		return light.color
	}
	
	func apply(_ preset: ColorPreset) {
		for target in targets where target.type.mixesColor {
			apply(preset.mix(emitters: target.type.emitters, mixing: target.type.mixing), to: target)
		}
	}
	
	func apply(_ light: LightColor) {
		apply(ColorPreset(name: "", recipe: .colour(light)))
	}
	
	func apply(kelvin: Double) {
		apply(ColorPreset(name: "", recipe: .white(kelvin: kelvin)))
	}
	
	var colorBinding: Binding<Color> {
		Binding { light.color } set: { apply(LightColor($0)) }
	}
	
	var kelvin: Double {
		ColorTemperature.nearest(to: light) ?? ColorTemperature.neutral
	}
	
	var selectedPresetID: String? {
		guard !macroOverridesMix, let target = targets.first(where: { $0.type.mixesColor }) else { return nil }
		guard target.type.emitterChannels.contains(where: { isActive($0) }) else { return nil }
		var selected: String?
		var closest = 0.025
		
		for preset in presets {
			let distance = preset.mix(emitters: target.type.emitters, mixing: target.type.mixing).light(target.type.mixing).normalised.distance(to: light)
			if distance < closest {
				closest = distance
				selected = preset.id
			}
		}
		
		return selected
	}
	
	var emitters: [Attribute] {
		var roles: [Attribute] = []
		
		for attribute in Emitter.mixingOrder + [.uv] where targets.contains(where: { $0.type.channel(attribute) != nil }) {
			roles.append(attribute)
		}
		
		return roles
	}
	
	var presets: [ColorPreset] { ColorPreset.all(emitters: emitters) }
	
	var emitterChannels: [FixtureChannel] { channels.filter(\.attribute.isEmitter) }
	
	var isSubtractive: Bool { targets.contains { $0.type.mixing == .subtractive } }
	
	func guardedBinding(_ channel: FixtureChannel) -> Binding<Double> {
		Binding { Double(rawValue(of: channel)) } set: { newValue in
			let wanted = whole(newValue, of: channel)
			
			guard !channel.isWide, (0...255).contains(wanted), let blocked = channel.functions.first(where: { $0.requiresConfirmation && $0.contains(UInt8(wanted)) }) else {
				setRawValue(wanted, of: channel)
				return
			}
			
			if blocked.from > 0 {
				setRawValue(Int(blocked.from) - 1, of: channel)
			} else {
				setRawValue(Int(blocked.to) + 1, of: channel)
			}
		}
	}
	
	private func whole(_ value: Double, of channel: FixtureChannel) -> Int {
		guard value > 0 else { return 0 }
		return value < Double(channel.maximum) ? Int(value.rounded()) : channel.maximum
	}
	
	var balancesWhite: Bool {
		targets.contains { $0.type.mixing == .additive && ($0.type.channel(.white) != nil || $0.type.channel(.amber) != nil) }
	}
	
	var temperatureChannel: FixtureChannel? {
		channel(.colorTemperature)
	}
	
	var macroChannel: FixtureChannel? {
		channel(.colorMacro) ?? channel(.colorWheel)
	}
	
	var macroOverridesMix: Bool {
		for target in targets where target.type.mixesColor {
			guard let macro = target.type.channel(.colorMacro) ?? target.type.channel(.colorWheel), let release = macro.functions.first(where: { $0.purpose == .release }) else { continue }
			if !release.contains(value(of: macro, in: target)) { return true }
		}
		
		return false
	}
	
	func release(_ group: FeatureGroup) {
		for target in targets {
			for channel in target.type.channels(in: group) {
				setRaw(channel.neutral, of: channel, in: target)
				console.release(target.span, only: channel.offset)
				
				if let fine = channel.fineOffset {
					console.release(target.span, only: fine)
				}
			}
		}
	}
	
	var address: String {
		guard let first = targets.first else { return "" }
		let span = first.span
		return targets.count == 1 ? "\(span.lowerBound)–\(span.upperBound)" : "\(targets.count) lights"
	}
	
	var groups: [FeatureGroup] {
		FeatureGroup.allCases.filter { group in
			switch group {
			case .dimmer: dims || !channels(in: group).isEmpty
			case .color: mixesColor || !channels(in: group).isEmpty
			case .position: movesHead || !channels(in: group).isEmpty
			case .gobo, .beam, .control: !channels(in: group).isEmpty
			}
		}
	}
	
	func channels(in group: FeatureGroup) -> [FixtureChannel] {
		channels.filter { $0.attribute.group == group }
	}
	
	func channel(_ attribute: Attribute) -> FixtureChannel? {
		channels.first { $0.attribute == attribute }
	}
	
	func blocker(of channel: FixtureChannel) -> FixtureChannel? {
		for target in targets {
			guard let own = counterpart(of: channel, in: target), let dependency = own.enabledBy, let address = address(dependency.offset, in: target) else { continue }
			if !dependency.contains(console.value(at: address)) { return target.type.channels.first { $0.offset == dependency.offset } }
		}
		
		return nil
	}
	
	var shutterChannel: FixtureChannel? {
		for target in targets {
			guard case let .band(dimmer, _, _, _) = target.type.dimming, let shared = channels.first(where: { $0.matches(dimmer) }) else { continue }
			return shared
		}
		
		return channel(.shutter)
	}
	
	var strobeHertz: Double? {
		guard let channel = shutterChannel, let function = band(of: channel), function.purpose == nil, function.kind == .proportional, function.unit == .hertz else { return nil }
		guard let from = function.physicalFrom, let to = function.physicalTo, function.to > function.from else { return nil }
		let share = Double(value(of: channel) - function.from) / Double(function.to - function.from)
		return from + (to - from) * share
	}
	
	func physical(of channel: FixtureChannel) -> String? {
		band(of: channel)?.physical(at: value(of: channel))
	}
	
	func degrees(_ attribute: Attribute) -> Double? {
		guard let channel = channel(attribute), let function = channel.functions.first, function.unit == .degrees else { return nil }
		guard let from = function.physicalFrom, let to = function.physicalTo else { return nil }
		return from + (to - from) * fraction(attribute)
	}
	
	func applyDefaults() {
		for target in targets {
			console.set(target.type.defaults, at: target.start)
			console.release(target.span)
		}
	}
	
	func centre() {
		setFraction(0.5, for: .pan)
		setFraction(0.5, for: .tilt)
	}
	
	func rawValue(of channel: FixtureChannel) -> Int {
		for target in targets {
			if let own = counterpart(of: channel, in: target) { return raw(of: own, in: target) }
		}
		
		return 0
	}
	
	func setRawValue(_ newValue: Int, of channel: FixtureChannel) {
		for target in targets {
			if let own = counterpart(of: channel, in: target) { setRaw(newValue, of: own, in: target) }
		}
	}
	
	func rawBinding(_ channel: FixtureChannel) -> Binding<Double> {
		Binding { Double(rawValue(of: channel)) } set: { setRawValue(whole($0, of: channel), of: channel) }
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
