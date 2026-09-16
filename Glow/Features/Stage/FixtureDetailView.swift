import SwiftData
import SwiftUI

/// Full control of one fixture, built from its profile.
///
/// The sections run in tier order — see ``DetailLevel`` for what the tiers are
/// and why they may not be reshuffled. Every section is also conditional on
/// the profile actually having those channels, so the same view drives a
/// one-channel dimmer and a fourteen-channel moving head without either
/// looking padded or truncated.
struct FixtureDetailView: View {
    @Environment(AppModel.self) private var model
    @Bindable var fixture: PatchedFixture

    @AppStorage(DetailLevel.storageKey) private var detail = DetailLevel.simple
    @State private var pendingConfirmation: PendingRange?

    private struct PendingRange: Identifiable {
        let channel: FixtureChannel
        let range: FixtureChannelRange
        var id: String { "\(channel.offset)-\(range.id)" }
    }

    private var profile: FixtureProfile? { model.profile(for: fixture) }
    private var control: FixtureControl? { model.control(for: fixture) }

    var body: some View {
        Form {
            if let profile, let control {
                disclosureSection
                brightnessSection(profile, control)
                FixtureColorControl(control: control, showsAdvanced: detail.showsRawValues)
                positionSection(profile, control)
                functionsSection(profile, control)
                actionsSection(profile, control)
                if detail == .full {
                    FixtureChannelControl(control: control, startAddress: fixture.startAddress)
                }
            } else {
                unknownProfileSection
            }
        }
        .formStyle(.grouped)
        .navigationTitle(fixture.name)
        .navigationSubtitle(subtitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ConnectionStatusView(compact: true)
                BlackoutButton(compact: true)
            }
        }
        .alert(item: $pendingConfirmation) { pending in
            Alert(
                title: Text("Send “\(pending.range.label)”?"),
                message: Text("This interrupts the fixture — the head may reset or the lamp may cut out for several seconds."),
                primaryButton: .destructive(Text("Send")) {
                    control?.setValue(pending.range.representativeValue, of: pending.channel)
                },
                secondaryButton: .cancel()
            )
        }
    }

    /// What this fixture is, in the navigation bar rather than in a row: it is
    /// the answer to "which light am I holding", which you want while you
    /// scroll, not once at the top.
    private var subtitle: String {
        guard let profile else { return "Profile missing" }
        // A freshly patched fixture is named after its model, so spelling the
        // model out again would cost the address its room in the bar.
        var parts: [String] = []
        if !fixture.name.localizedCaseInsensitiveContains(profile.model) {
            parts.append(profile.displayName)
        }
        if !profile.mode.isEmpty { parts.append(profile.mode) }
        if detail.showsRawValues {
            let range = Patch.range(of: fixture, profile: profile)
            parts.append("DMX \(range.lowerBound)–\(range.upperBound)")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Disclosure and settings

    private var disclosureSection: some View {
        Section {
            DetailLevelPicker(selection: $detail)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))

            NavigationLink {
                FixtureSettingsView(fixture: fixture)
            } label: {
                Label("Fixture settings", systemImage: "gearshape")
            }
        } footer: {
            Text(detail.explanation)
        }
    }

    // MARK: - Tier 1

    @ViewBuilder
    private func brightnessSection(_ profile: FixtureProfile, _ control: FixtureControl) -> some View {
        if control.supportsIntensity {
            Section {
                LevelFader(
                    title: "Level",
                    systemImage: "sun.max",
                    tint: .yellow,
                    value: control.intensityBinding
                )

                HStack(spacing: 6) {
                    ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { level in
                        Button {
                            withAnimation(.snappy) { control.intensity = level }
                        } label: {
                            Text(level, format: .percent.precision(.fractionLength(0)))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .font(.caption.monospacedDigit())
            } header: {
                Text("Brightness")
            } footer: {
                Text(brightnessExplanation(profile))
            }
        }
    }

    /// Says how this fixture actually dims. On half a small rig it is not a
    /// dimmer channel, and the difference turns up as surprising behaviour if
    /// nothing says so.
    private func brightnessExplanation(_ profile: FixtureProfile) -> String {
        switch profile.intensityModel {
        case .dedicated:
            detail.showsRawValues ? "Drives this fixture's dimmer channel." : ""

        case let .band(channel, from, to, _):
            detail.showsRawValues
                ? "“\(channel.name)” is one channel doing two jobs, so the level maps into its dimming band (\(from)–\(to)) rather than the full range."
                : "This fixture dims and strobes on the same channel, so the slider uses only the part of it that dims."

        case .virtual:
            "This fixture has no dimmer, so the slider scales the colour mix and keeps the hue."

        case .none:
            ""
        }
    }

    @ViewBuilder
    private func positionSection(_ profile: FixtureProfile, _ control: FixtureControl) -> some View {
        if profile.hasMovement {
            Section {
                PositionPad(
                    pan: control.normalisedBinding(.pan),
                    tilt: control.normalisedBinding(.tilt),
                    panDegrees: profile.panDegrees,
                    tiltDegrees: profile.tiltDegrees
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

                ActionRow(
                    title: "Centre",
                    systemImage: "arrow.up.and.down.and.arrow.left.and.right"
                ) {
                    withAnimation(.snappy) {
                        control.setNormalised(0.5, for: .pan)
                        control.setNormalised(0.5, for: .tilt)
                    }
                }

                if detail == .full {
                    LevelFader(title: "Pan", systemImage: "arrow.left.and.right", value: control.normalisedBinding(.pan))
                    LevelFader(title: "Tilt", systemImage: "arrow.up.and.down", value: control.normalisedBinding(.tilt))

                    if let speed = profile.channel(role: .movementSpeed) {
                        ChannelFader(
                            title: speed.name,
                            subtitle: "0 is fastest on most fixtures.",
                            value: control.binding(for: speed)
                        )
                    }
                }
            } header: {
                Text("Position")
            } footer: {
                Text("Drag the pad to point the light. Up on the pad points the head up.")
            }
        }
    }

    // MARK: - Tier 2

    /// Channels whose manual describes named bands rather than a continuous
    /// sweep — shutter, gobo, colour macro, mode. A menu of the fixture's own
    /// words beats a fader you have to land on the right value with.
    @ViewBuilder
    private func functionsSection(_ profile: FixtureProfile, _ control: FixtureControl) -> some View {
        let ranged = profile.channels.filter { !$0.ranges.isEmpty }
        if !ranged.isEmpty {
            Section {
                ForEach(ranged) { channel in
                    RangedChannelRow(
                        channel: channel,
                        control: control,
                        showsRawValues: detail.showsRawValues,
                        onConfirmationNeeded: { range in
                            pendingConfirmation = PendingRange(channel: channel, range: range)
                        }
                    )
                }
            } header: {
                Text("Functions")
            } footer: {
                Text("Built into the fixture, named the way its own manual names them.")
            }
        }
    }

    // MARK: - Actions

    private func actionsSection(_ profile: FixtureProfile, _ control: FixtureControl) -> some View {
        Section {
            ActionRow(
                title: "Home",
                subtitle: homeSubtitle(profile, control),
                systemImage: "scope"
            ) {
                withAnimation(.snappy) { control.home() }
            }

            ActionRow(title: "Reset to profile defaults", systemImage: "arrow.counterclockwise") {
                withAnimation(.snappy) { control.applyDefaults() }
            }

            if control.supportsIntensity {
                ActionRow(title: "Zero the level", systemImage: "arrow.down.to.line") {
                    withAnimation(.snappy) { control.zeroIntensity() }
                }
            }
        } header: {
            Text("Actions")
        } footer: {
            Text("Home is where to come back to when a fixture is not doing what you expect. Reset only puts the channels back where the profile says they belong, without moving the light or bringing it up.")
        }
    }

    /// Spelled out rather than left as jargon: "Home" is one word and up to
    /// three separate changes, and which three depends on the fixture.
    private func homeSubtitle(_ profile: FixtureProfile, _ control: FixtureControl) -> String {
        var parts: [String] = []
        if profile.hasMovement { parts.append("centres the head") }
        if control.supportsIntensity { parts.append("brings it up") }
        if control.supportsColor { parts.append("goes to white") }
        guard !parts.isEmpty else { return "Puts every channel back to its default." }
        return parts.joined(separator: ", ").capitalisingFirstLetter + "."
    }

    // MARK: - Failure

    private var unknownProfileSection: some View {
        Section {
            ContentUnavailableView {
                Label("Profile missing", systemImage: "questionmark.circle")
            } description: {
                Text("Nothing in the library has the id “\(fixture.profileID)”, so Glow does not know what this fixture's channels do. Re-patch it from the library to fix this.")
            }
        }
    }
}

/// A channel with named bands: a menu to choose one, and a fader scoped to the
/// band when the band is a continuous parameter like a strobe rate.
struct RangedChannelRow: View {
    let channel: FixtureChannel
    let control: FixtureControl
    var showsRawValues = false
    let onConfirmationNeeded: (FixtureChannelRange) -> Void

    private var value: UInt8 { control.value(of: channel) }
    private var activeRange: FixtureChannelRange? { channel.range(containing: value) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(channel.name, systemImage: channel.role.symbolName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                menu
            }

            if showsRawValues, let address = control.address(of: channel) {
                Text("DMX \(address.rawValue) · \(Int(value))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let activeRange, activeRange.kind == .proportional {
                Slider(
                    value: Binding(
                        get: { Double(value) },
                        set: { control.setValue(UInt8($0.rounded()), of: channel) }
                    ),
                    in: Double(activeRange.from)...Double(activeRange.to),
                    step: 1
                ) {
                    Text(activeRange.label)
                }
                .accessibilityLabel("\(channel.name), \(activeRange.label)")
            }
        }
    }

    private var menu: some View {
        Menu {
            ForEach(channel.ranges) { range in
                Button {
                    if range.requiresConfirmation {
                        onConfirmationNeeded(range)
                    } else {
                        control.setValue(range.representativeValue, of: channel)
                    }
                } label: {
                    if range.requiresConfirmation {
                        Label(range.label, systemImage: "exclamationmark.triangle")
                    } else {
                        Text(range.label)
                    }
                }
            }
        } label: {
            Text(activeRange?.label ?? "Value \(Int(value))")
                .font(.subheadline)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(channel.name)
        .accessibilityValue(activeRange?.label ?? "\(Int(value))")
    }
}

extension String {
    /// Sentence-cases a phrase assembled from fragments, without touching the
    /// rest — `localizedCapitalized` would also capitalise "White".
    var capitalisingFirstLetter: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
