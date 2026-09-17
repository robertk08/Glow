import SwiftUI

@MainActor
struct SelectionControl {
	let fixtures: [Fixture]
	let controls: [FixtureControl]
	
	init(fixtures: [Fixture], library: FixtureLibrary, console: Console) {
		self.fixtures = fixtures
		controls = fixtures.compactMap { FixtureControl(fixture: $0, library: library, console: console) }
	}
	
	var title: String {
		fixtures.count == 1 ? fixtures[0].name : "\(fixtures.count) Lights"
	}
	
	var single: FixtureControl? {
		controls.count == 1 ? controls[0] : nil
	}
	
	var profile: FixtureProfile? {
		guard let first = controls.first, controls.allSatisfy({ $0.profile.id == first.profile.id }) else { return nil }
		return first.profile
	}
	
	var dims: Bool { controls.contains(where: \.dims) }
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
	
	var emitters: [ChannelRole] {
		var roles: [ChannelRole] = []
		
		for role in Emitter.mixingOrder + [.uv] where controls.contains(where: { $0.profile.channel(role) != nil }) {
			roles.append(role)
		}
		
		return roles
	}
	
	var presets: [ColorPreset] { ColorPreset.all(for: emitters) }
	
	var light: LightColor {
		controls.first { $0.profile.mixesColor }?.mix.light.normalised ?? .black
	}
	
	var colorBinding: Binding<Color> {
		Binding { light.color } set: { apply(LightColor($0)) }
	}
	
	var kelvin: Double {
		ColorTemperature.nearest(to: light) ?? ColorTemperature.neutral
	}
	
	func apply(_ light: LightColor) {
		for control in controls where control.profile.mixesColor {
			control.apply(.mixing(light, with: control.profile.emitterChannels.map(\.role)))
		}
	}
	
	func apply(_ preset: ColorPreset) {
		for control in controls where control.profile.mixesColor {
			control.apply(preset.mix(with: control.profile.emitterChannels.map(\.role)))
		}
	}
	
	func apply(kelvin: Double) {
		for control in controls where control.profile.mixesColor {
			control.apply(.white(kelvin: kelvin, with: control.profile.emitterChannels.map(\.role)))
		}
	}
	
	var macroOverridesMix: Bool {
		controls.contains(where: \.macroOverridesMix)
	}
	
	func releaseMix() {
		for control in controls {
			control.releaseMix()
		}
	}
	
	func fraction(_ role: ChannelRole) -> Double {
		controls.first { $0.profile.channel(role) != nil }?.fraction(role) ?? 0.5
	}
	
	func fractionBinding(_ role: ChannelRole) -> Binding<Double> {
		Binding { fraction(role) } set: { value in
			for control in controls {
				control.setFraction(value, for: role)
			}
		}
	}
	
	func centre() {
		for control in controls where control.profile.movesHead {
			control.setFraction(0.5, for: .pan)
			control.setFraction(0.5, for: .tilt)
		}
	}
	
	var settings: [ProfileChannel] {
		guard profile != nil, let first = controls.first else { return [] }
		return first.settings
	}
	
	var emitterChannels: [ProfileChannel] {
		profile?.emitterChannels ?? []
	}
	
	func value(of channel: ProfileChannel) -> UInt8 {
		controls.first?.value(of: channel) ?? 0
	}
	
	func band(of channel: ProfileChannel) -> ChannelRange? {
		channel.range(containing: value(of: channel))
	}
	
	func set(_ value: UInt8, of channel: ProfileChannel) {
		for control in controls {
			control.set(value, of: channel)
		}
	}
	
	func binding(_ channel: ProfileChannel) -> Binding<Double> {
		Binding { Double(value(of: channel)) } set: { set(UInt8(min(max($0.rounded(), 0), 255)), of: channel) }
	}
	
	func home() {
		for control in controls {
			control.home()
		}
	}
	
	func applyDefaults() {
		for control in controls {
			control.applyDefaults()
		}
	}
}
