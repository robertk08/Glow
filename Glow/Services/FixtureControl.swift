import SwiftUI

@MainActor
struct FixtureControl {
    let profile: FixtureProfile
    let start: DMXAddress
    let console: Console
    
    init(profile: FixtureProfile, start: DMXAddress, console: Console) {
        self.profile = profile
        self.start = start
        self.console = console
    }
    
    init?(fixture: Fixture, library: FixtureLibrary, console: Console) {
        guard let profile = library.profile(fixture.profileID) else { return nil }
        self.profile = profile
        start = fixture.start
        self.console = console
    }
    
    var hue: Double {
        get { mix.light.normalised.hue / 360 }
        nonmutating set { apply(.mixing(LightColor(hue: newValue, saturation: saturation), with: profile.emitterChannels.map(\.role))) }
    }
    
    var saturation: Double {
        get { mix.light.normalised.saturation }
        nonmutating set { apply(.mixing(LightColor(hue: hue, saturation: newValue), with: profile.emitterChannels.map(\.role))) }
    }
    
    var kelvin: Double {
        get { ColorTemperature.nearest(to: mix.light.normalised) ?? ColorTemperature.neutral }
        nonmutating set { apply(.white(kelvin: newValue, with: profile.emitterChannels.map(\.role))) }
    }
    
    var balancesWhite: Bool {
        profile.channel(.white) != nil || profile.channel(.amber) != nil
    }
    
    var hueBinding: Binding<Double> {
        Binding { hue } set: { hue = $0 }
    }
    
    var saturationBinding: Binding<Double> {
        Binding { saturation } set: { saturation = $0 }
    }
    
    var kelvinBinding: Binding<Double> {
        Binding { kelvin } set: { kelvin = $0 }
    }
    
    func address(of channel: ProfileChannel) -> DMXAddress? {
        start.offset(by: channel.offset - 1)
    }
    
    func value(of channel: ProfileChannel) -> UInt8 {
        address(of: channel).map { console.value(at: $0) } ?? 0
    }
    
    func set(_ value: UInt8, of channel: ProfileChannel) {
        guard let address = address(of: channel) else { return }
        console.set(value, at: address)
    }
    
    func binding(_ channel: ProfileChannel) -> Binding<Double> {
        Binding(
            get: { Double(value(of: channel)) },
            set: { set(UInt8(min(max($0.rounded(), 0), 255)), of: channel) }
        )
    }
    
    func fraction(_ role: ChannelRole) -> Double {
        guard let coarse = profile.channel(role) else { return 0 }
        let high = Double(value(of: coarse))
        guard let fine = profile.channel(role, fine: true) else { return high / 255 }
        return (high * 256 + Double(value(of: fine))) / 65535
    }
    
    func setFraction(_ newValue: Double, for role: ChannelRole) {
        guard let coarse = profile.channel(role) else { return }
        let clamped = min(max(newValue, 0), 1)
        
        guard let fine = profile.channel(role, fine: true) else {
            set(UInt8((clamped * 255).rounded()), of: coarse)
            return
        }
        
        let combined = UInt16((clamped * 65535).rounded())
        set(UInt8(combined >> 8), of: coarse)
        set(UInt8(combined & 0xFF), of: fine)
    }
    
    func fractionBinding(_ role: ChannelRole) -> Binding<Double> {
        Binding(get: { fraction(role) }, set: { setFraction($0, for: role) })
    }
    
    var dims: Bool { profile.dims }
    
    var brightness: Double {
        get {
            switch profile.dimming {
            case .channel:
                fraction(.intensity)
            case let .band(channel, from, to, _):
                switch value(of: channel) {
                case ..<from: 0
                case from...to: Double(value(of: channel) - from) / Double(max(1, to - from))
                default: 1
                }
            case let .emitters(channels):
                Double(channels.map { value(of: $0) }.max() ?? 0) / 255
            case .none:
                0
            }
        }
        nonmutating set {
            let level = min(max(newValue, 0), 1)
            
            switch profile.dimming {
            case .channel:
                setFraction(level, for: .intensity)
            case let .band(channel, from, to, open):
                if level <= 0 {
                    set(0, of: channel)
                } else if level >= 1, let open {
                    set(open, of: channel)
                } else {
                    set(from + UInt8((Double(to - from) * level).rounded()), of: channel)
                }
            case let .emitters(channels):
                let current = channels.map { Double(value(of: $0)) }
                let peak = current.max() ?? 0
                let target = level * 255
                
                if peak == 0 {
                    for channel in channels { set(UInt8(target.rounded()), of: channel) }
                } else {
                    for (channel, existing) in zip(channels, current) {
                        set(UInt8(min(max((existing * target / peak).rounded(), 0), 255)), of: channel)
                    }
                }
            case .none:
                break
            }
        }
    }
    
    var brightnessBinding: Binding<Double> {
        Binding(get: { brightness }, set: { brightness = $0 })
    }
    
    var dimmers: [Console.Dimmer] {
        switch profile.dimming {
        case let .channel(channel):
            address(of: channel).map { [Console.Dimmer(address: $0, kind: .linear)] } ?? []
        case let .band(channel, from, to, open):
            address(of: channel).map {
                [Console.Dimmer(address: $0, kind: .band(from: from, to: to, open: open))]
            } ?? []
        case let .emitters(channels):
            channels.compactMap { channel in
                address(of: channel).map { Console.Dimmer(address: $0, kind: .linear) }
            }
        case .none:
            []
        }
    }
    
    var mix: EmitterMix {
        var mix = EmitterMix()
        for channel in profile.emitterChannels {
            mix[channel.role] = Double(value(of: channel)) / 255
        }
        return mix
    }
    
    func apply(_ mix: EmitterMix) {
        let peak = profile.emitterChannels
            .map { Double(value(of: $0)) / 255 }
            .max() ?? 0
        let level = peak > 0 ? peak : 1
        let recipe = mix.normalised
        
        for channel in profile.emitterChannels {
            set(UInt8(min(max((recipe[channel.role] * level * 255).rounded(), 0), 255)), of: channel)
        }
    }
    
    var displayColor: Color {
        mix.light.color
    }
    
    var macro: ProfileChannel? {
        profile.channel(.colorMacro) ?? profile.channel(.colorWheel)
    }
    
    var macroOverridesMix: Bool {
        guard profile.mixesColor, let macro, let release = releaseBand(of: macro) else { return false }
        return !release.contains(value(of: macro))
    }
    
    func releaseMix() {
        guard let macro, let release = releaseBand(of: macro) else { return }
        set(release.midpoint, of: macro)
    }
    
    func releaseBand(of channel: ProfileChannel) -> ChannelRange? {
        if let declared = channel.ranges.first(where: \.releasesMix) { return declared }
        return channel.ranges.min { $0.from < $1.from }
    }
    
    var settings: [ProfileChannel] {
        var shown: Set<Int> = []
        
        for channel in profile.emitterChannels where profile.mixesColor {
            shown.insert(channel.offset)
        }
        
        if profile.mixesColor, let macro {
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
        console.set(profile.defaults, at: start)
    }
    
    func home() {
        applyDefaults()
        if profile.movesHead {
            setFraction(0.5, for: .pan)
            setFraction(0.5, for: .tilt)
        }
        if profile.mixesColor {
            apply(.white(kelvin: ColorTemperature.neutral, with: profile.emitterChannels.map(\.role)))
        }
        if dims {
            brightness = 1
        }
    }
    
    var parameters: [FixtureParameter] {
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
    
    func addressLabel(of parameter: FixtureParameter) -> String {
        guard let first = address(of: parameter.coarse) else { return "" }
        guard let fine = parameter.fine, let second = address(of: fine) else {
            return "\(first.value)"
        }
        return "\(first.value)+\(second.value)"
    }
}
