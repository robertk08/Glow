import SwiftUI

/// A window onto the span of the universe one patched fixture occupies.
///
/// Created fresh wherever it is needed and never stored: it holds no state of
/// its own, only a profile, an address and the engine. Reading gives whatever
/// is in the universe right now, writing goes straight there.
@MainActor struct FixtureControl {
    let profile: FixtureProfile
    let startAddress: DMXAddress
    let engine: ConsoleEngine

    // MARK: - Raw channels

    func address(of channel: FixtureChannel) -> DMXAddress? {
        startAddress.offset(by: channel.offset - 1)
    }

    func value(of channel: FixtureChannel) -> UInt8 {
        guard let address = address(of: channel) else { return 0 }
        return engine.value(at: address)
    }

    func setValue(_ value: UInt8, of channel: FixtureChannel) {
        guard let address = address(of: channel) else { return }
        engine.set(value, at: address)
    }

    /// Binding for a plain 8-bit fader.
    func binding(for channel: FixtureChannel) -> Binding<Double> {
        Binding(
            get: { Double(value(of: channel)) },
            set: { setValue(UInt8(($0).rounded().clamped(to: 0...255)), of: channel) }
        )
    }

    // MARK: - 16-bit pairs

    /// Reads a role as a normalised 0...1, using the fine channel when the
    /// fixture has one. A head with 16-bit pan has 65,536 positions across its
    /// travel, and losing that to an 8-bit slider is visible as stepping on a
    /// slow move across a room.
    func normalised(_ role: ChannelRole) -> Double {
        guard let coarse = profile.channel(role: role, fine: false) else { return 0 }
        let high = Double(value(of: coarse))
        guard let fine = profile.channel(role: role, fine: true) else { return high / 255 }
        return (high * 256 + Double(value(of: fine))) / 65535
    }

    func setNormalised(_ newValue: Double, for role: ChannelRole) {
        guard let coarse = profile.channel(role: role, fine: false) else { return }
        let clamped = newValue.clamped(to: 0...1)

        guard let fine = profile.channel(role: role, fine: true) else {
            setValue(UInt8((clamped * 255).rounded()), of: coarse)
            return
        }

        let combined = UInt16((clamped * 65535).rounded())
        setValue(UInt8(combined >> 8), of: coarse)
        setValue(UInt8(combined & 0xFF), of: fine)
    }

    func normalisedBinding(_ role: ChannelRole) -> Binding<Double> {
        Binding(
            get: { normalised(role) },
            set: { setNormalised($0, for: role) }
        )
    }

    var hasRole: (ChannelRole) -> Bool {
        { role in profile.channel(role: role) != nil }
    }

    // MARK: - Intensity

    var supportsIntensity: Bool { profile.hasControllableIntensity }

    /// Brightness as 0...1, whatever the fixture actually uses to get there.
    var intensity: Double {
        get {
            switch profile.intensityModel {
            case .dedicated:
                normalised(.intensity)

            case let .band(channel, from, to, openFrom):
                switch value(of: channel) {
                case ..<from: 0
                case from...to: Double(value(of: channel) - from) / Double(max(1, to - from))
                default: 1  // open, or strobing, both of which are full output
                }

            case let .virtual(channels):
                Double(channels.map { value(of: $0) }.max() ?? 0) / 255

            case .none:
                0
            }
        }
        nonmutating set {
            let level = newValue.clamped(to: 0...1)

            switch profile.intensityModel {
            case .dedicated:
                setNormalised(level, for: .intensity)

            case let .band(channel, from, to, openFrom):
                if level <= 0 {
                    setValue(0, of: channel)
                } else if level >= 1, let openFrom {
                    setValue(openFrom, of: channel)
                } else {
                    setValue(from + UInt8((Double(to - from) * level).rounded()), of: channel)
                }

            case let .virtual(channels):
                // Scale the mix, preserving hue. From black there is no hue to
                // preserve, so it comes up white — which is what you want when
                // you push a fader up on a dark fixture.
                let current = channels.map { Double(value(of: $0)) }
                let peak = current.max() ?? 0
                let target = level * 255

                if peak == 0 {
                    for channel in channels { setValue(UInt8(target.rounded()), of: channel) }
                } else {
                    let factor = target / peak
                    for (channel, existing) in zip(channels, current) {
                        setValue(UInt8((existing * factor).clamped(to: 0...255).rounded()), of: channel)
                    }
                }

            case .none:
                break
            }
        }
    }

    var intensityBinding: Binding<Double> {
        Binding(get: { intensity }, set: { intensity = $0 })
    }

    /// How the grand master should scale this fixture on the way to the wire.
    var intensityScalers: [IntensityScaler] {
        switch profile.intensityModel {
        case let .dedicated(channel):
            address(of: channel).map { [IntensityScaler(address: $0, kind: .linear)] } ?? []

        case let .band(channel, from, to, openFrom):
            address(of: channel).map {
                [IntensityScaler(address: $0, kind: .band(from: from, to: to, openFrom: openFrom))]
            } ?? []

        case let .virtual(channels):
            channels.compactMap { channel in
                address(of: channel).map { IntensityScaler(address: $0, kind: .linear) }
            }

        case .none:
            []
        }
    }

    // MARK: - Colour

    var supportsColor: Bool { profile.hasColorMixing }

    /// The mixed colour, as far as RGB can represent it. White, amber and UV
    /// channels are controlled separately — folding them into an RGB picker
    /// would make them unreachable, and on most fixtures they are the
    /// difference between a usable wash and a tinted one.
    var color: Color {
        get {
            Color(
                red: channelFraction(.red),
                green: channelFraction(.green),
                blue: channelFraction(.blue)
            )
        }
        nonmutating set {
            let components = newValue.rgbComponents
            setChannelFraction(.red, components.red)
            setChannelFraction(.green, components.green)
            setChannelFraction(.blue, components.blue)
        }
    }

    var colorBinding: Binding<Color> {
        Binding(get: { color }, set: { color = $0 })
    }

    func channelFraction(_ role: ChannelRole) -> Double {
        guard let channel = profile.channel(role: role) else { return 0 }
        return Double(value(of: channel)) / 255
    }

    func setChannelFraction(_ role: ChannelRole, _ fraction: Double) {
        guard let channel = profile.channel(role: role) else { return }
        setValue(UInt8((fraction.clamped(to: 0...1) * 255).rounded()), of: channel)
    }

    /// Mixing channels beyond red/green/blue, which get their own faders.
    var auxiliaryColorChannels: [FixtureChannel] {
        profile.colorMixingChannels.filter { ![.red, .green, .blue].contains($0.role) }
    }

    // MARK: - Actions

    /// Puts every channel where the profile says it belongs. This is what
    /// makes a freshly patched fixture actually respond: on many heads a mode
    /// or macro channel left at zero silently overrides everything else.
    func applyDefaults() {
        engine.apply(profile.defaultValues, startingAt: startAddress)
    }

    /// Centred, open, white — the state you want when you have lost track of
    /// where a head is pointing.
    func home() {
        applyDefaults()
        if profile.hasMovement {
            setNormalised(0.5, for: .pan)
            setNormalised(0.5, for: .tilt)
        }
        if supportsColor {
            setChannelFraction(.red, 1)
            setChannelFraction(.green, 1)
            setChannelFraction(.blue, 1)
        }
        if supportsIntensity {
            setNormalised(1, for: .intensity)
        }
    }

    func zeroIntensity() {
        if supportsIntensity {
            setNormalised(0, for: .intensity)
        } else {
            for channel in profile.colorMixingChannels {
                setValue(0, of: channel)
            }
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension Color {
    /// sRGB components, for turning a picker selection into channel values.
    var rgbComponents: (red: Double, green: Double, blue: Double) {
        let resolved = UIColor(self)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (Double(red), Double(green), Double(blue))
    }
}
