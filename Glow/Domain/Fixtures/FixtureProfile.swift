import Foundation

/// A named band of values within one channel — "open", "strobe 1-20 Hz",
/// "gobo 4", "reset".
nonisolated struct FixtureChannelRange: Codable, Hashable, Sendable, Identifiable {
    /// How the band behaves, which decides what control the UI offers.
    nonisolated enum Kind: String, Codable, Sendable {
        /// One setting covering a span — a gobo, a colour macro. Picking it
        /// jumps to the middle of the band.
        case discrete
        /// A continuous parameter — dimming, strobe rate. Offers a fader
        /// scoped to the band.
        case proportional
    }

    var from: UInt8
    var to: UInt8
    var label: String
    var kind: Kind = .discrete

    /// Marks the band on a macro or wheel channel that leaves the emitter
    /// faders in charge.
    ///
    /// Every manufacturer parks "the console decides" somewhere on the channel
    /// and labels it differently — "RGBW mix", "Off (RGB faders active)",
    /// "Open (white)". Saying so in the profile beats matching on wording,
    /// which works until a profile arrives in German.
    var releasesMix: Bool = false

    /// Bands that do something disruptive — a lamp strike, a motor reset, a
    /// factory wipe. The UI asks before entering one, because on several of
    /// these fixtures a stray drag across the fader resets the head mid-show.
    var requiresConfirmation: Bool = false

    var id: String { "\(from)-\(to)-\(label)" }

    /// The value to send when this band is chosen: its midpoint, which is the
    /// safest place to sit when manufacturers disagree with their own manuals
    /// about where a band starts.
    var representativeValue: UInt8 {
        UInt8((Int(from) + Int(to)) / 2)
    }

    func contains(_ value: UInt8) -> Bool { (from...to).contains(value) }

    // Synthesised decoding ignores default values and demands every key, which
    // would make each of the profiles spell out fields that are almost always
    // the same. These decoders let a profile say only what is interesting.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        from = try container.decode(UInt8.self, forKey: .from)
        to = try container.decode(UInt8.self, forKey: .to)
        label = try container.decode(String.self, forKey: .label)
        kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .discrete
        requiresConfirmation = try container.decodeIfPresent(Bool.self, forKey: .requiresConfirmation) ?? false
        releasesMix = try container.decodeIfPresent(Bool.self, forKey: .releasesMix) ?? false
    }

    init(
        from: UInt8,
        to: UInt8,
        label: String,
        kind: Kind = .discrete,
        requiresConfirmation: Bool = false,
        releasesMix: Bool = false
    ) {
        self.from = from
        self.to = to
        self.label = label
        self.kind = kind
        self.requiresConfirmation = requiresConfirmation
        self.releasesMix = releasesMix
    }
}

/// One channel of a fixture, as an offset from the fixture's start address.
nonisolated struct FixtureChannel: Codable, Hashable, Sendable, Identifiable {
    /// 1-based offset from the fixture's start address. Channel 1 of a fixture
    /// patched at 100 is DMX address 100.
    var offset: Int
    var role: ChannelRole
    var name: String

    /// True when this is the low byte of a 16-bit pair whose high byte carries
    /// the same role. Pan and tilt are the usual case.
    var isFine: Bool = false

    /// Where the channel sits when the fixture is patched.
    ///
    /// These are not cosmetic. On many fixtures a handful of channels decide
    /// whether the fixture listens to DMX at all — a mode channel parked in an
    /// auto-program band will happily move the head while ignoring every other
    /// channel you send. The defaults encode the "responds to DMX" state.
    var defaultValue: UInt8 = 0

    var ranges: [FixtureChannelRange] = []

    var id: Int { offset }

    func range(containing value: UInt8) -> FixtureChannelRange? {
        ranges.first { $0.contains(value) }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        offset = try container.decode(Int.self, forKey: .offset)
        role = try container.decodeIfPresent(ChannelRole.self, forKey: .role) ?? .custom
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? (role == .custom ? "Channel \(offset)" : role.localizedName)
        isFine = try container.decodeIfPresent(Bool.self, forKey: .isFine) ?? false
        defaultValue = try container.decodeIfPresent(UInt8.self, forKey: .defaultValue) ?? 0
        ranges = try container.decodeIfPresent([FixtureChannelRange].self, forKey: .ranges) ?? []
    }

    init(
        offset: Int,
        role: ChannelRole,
        name: String? = nil,
        isFine: Bool = false,
        defaultValue: UInt8 = 0,
        ranges: [FixtureChannelRange] = []
    ) {
        self.offset = offset
        self.role = role
        self.name = name ?? role.localizedName
        self.isFine = isFine
        self.defaultValue = defaultValue
        self.ranges = ranges
    }
}

/// A fixture type: what its channels are and what they do.
///
/// Profiles are data, not code. They ship as JSON in the bundle and are
/// matched to patched fixtures by ``id``, so adding support for a new fixture
/// is a file, never a release of the firmware.
nonisolated struct FixtureProfile: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var manufacturer: String
    var model: String
    /// The mode name as the fixture's own display calls it — "14 channel".
    var mode: String
    var channels: [FixtureChannel]

    /// SF Symbol representing the fixture shape in the patch and stage lists.
    var symbolName: String = "lightbulb"

    /// Mechanical pan/tilt travel in degrees, for labelling the position pad.
    var panDegrees: Double?
    var tiltDegrees: Double?

    var notes: String?

    /// Set on the one profile that describes hardware the user actually owns,
    /// so it sorts to the top of the library.
    var isOwned: Bool = false

    var channelCount: Int { channels.map(\.offset).max() ?? 0 }

    var displayName: String {
        manufacturer.isEmpty ? model : "\(manufacturer) \(model)"
    }

    func channel(role: ChannelRole, fine: Bool = false) -> FixtureChannel? {
        channels.first { $0.role == role && $0.isFine == fine }
    }

    func channels(role: ChannelRole) -> [FixtureChannel] {
        channels.filter { $0.role == role }
    }

    var colorMixingChannels: [FixtureChannel] {
        channels.filter { $0.role.isColorMixing && !$0.isFine }
    }

    var hasColorMixing: Bool { colorMixingChannels.count >= 3 }
    var hasMovement: Bool { channel(role: .pan) != nil && channel(role: .tilt) != nil }
    var hasIntensity: Bool { channel(role: .intensity) != nil }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        manufacturer = try container.decodeIfPresent(String.self, forKey: .manufacturer) ?? "Generic"
        model = try container.decode(String.self, forKey: .model)
        mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? ""
        channels = try container.decode([FixtureChannel].self, forKey: .channels)
        symbolName = try container.decodeIfPresent(String.self, forKey: .symbolName) ?? "lightbulb"
        panDegrees = try container.decodeIfPresent(Double.self, forKey: .panDegrees)
        tiltDegrees = try container.decodeIfPresent(Double.self, forKey: .tiltDegrees)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        isOwned = try container.decodeIfPresent(Bool.self, forKey: .isOwned) ?? false
    }

    init(
        id: String,
        manufacturer: String = "Generic",
        model: String,
        mode: String = "",
        channels: [FixtureChannel],
        symbolName: String = "lightbulb",
        panDegrees: Double? = nil,
        tiltDegrees: Double? = nil,
        notes: String? = nil,
        isOwned: Bool = false
    ) {
        self.id = id
        self.manufacturer = manufacturer
        self.model = model
        self.mode = mode
        self.channels = channels
        self.symbolName = symbolName
        self.panDegrees = panDegrees
        self.tiltDegrees = tiltDegrees
        self.notes = notes
        self.isOwned = isOwned
    }

    /// The values a freshly patched fixture should be given.
    var defaultValues: [UInt8] {
        var values = [UInt8](repeating: 0, count: channelCount)
        for channel in channels where (1...channelCount).contains(channel.offset) {
            values[channel.offset - 1] = channel.defaultValue
        }
        return values
    }
}

/// How a fixture's brightness is actually reached.
///
/// Only some fixtures have a dedicated dimmer. Cheap moving heads merge the
/// dimmer into a shutter channel with banded values, and plain RGB pars have
/// no dimmer at all — on those, brightness *is* the colour. A console that
/// only understood the first case would leave the intensity fader and the
/// grand master doing nothing on most of a small rig, which is precisely the
/// rig this app is for.
nonisolated enum IntensityModel: Sendable, Equatable {
    /// A channel that means brightness and nothing else.
    case dedicated(FixtureChannel)

    /// A band inside a combined dimmer/strobe channel.
    case band(FixtureChannel, from: UInt8, to: UInt8, openFrom: UInt8?)

    /// No dimmer: scale the colour mixing channels together, which is what
    /// every desk does for an RGB fixture.
    case virtual([FixtureChannel])

    /// Fog machines, lasers — nothing here is a brightness.
    case none
}

extension FixtureProfile {
    var intensityModel: IntensityModel {
        if let dedicated = channel(role: .intensity, fine: false) {
            return .dedicated(dedicated)
        }

        if let shutter = channel(role: .shutter),
           let dimming = Self.dimmingBand(of: shutter) {
            let open = shutter.ranges.first {
                $0.kind == .discrete && $0.label.localizedCaseInsensitiveContains("open")
            }
            return .band(shutter, from: dimming.from, to: dimming.to, openFrom: open?.from)
        }

        let mixing = colorMixingChannels
        return mixing.isEmpty ? .none : .virtual(mixing)
    }

    /// The proportional band that dims rather than strobes.
    private static func dimmingBand(of channel: FixtureChannel) -> FixtureChannelRange? {
        let proportional = channel.ranges.filter { $0.kind == .proportional }
        if let named = proportional.first(where: { $0.label.localizedCaseInsensitiveContains("dim") }) {
            return named
        }
        return proportional
            .filter { !$0.label.localizedCaseInsensitiveContains("strob") }
            .min { $0.from < $1.from }
    }

    var hasControllableIntensity: Bool { intensityModel != .none }
}
