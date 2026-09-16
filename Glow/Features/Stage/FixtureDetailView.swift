import SwiftData
import SwiftUI

/// Full control of one fixture, built from its profile.
///
/// Every section here is conditional on the profile actually having those
/// channels, so the same view drives a one-channel dimmer and a fourteen
/// channel moving head without either looking padded or truncated.
struct FixtureDetailView: View {
    @Environment(AppModel.self) private var model
    @Bindable var fixture: PatchedFixture

    @State private var showingRawChannels = false
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
                intensitySection(profile, control)
                colorSection(profile, control)
                positionSection(profile, control)
                rangedSections(profile, control)
                rawSection(profile, control)
                actionsSection(control)
            } else {
                Section {
                    ContentUnavailableView(
                        "Unknown profile",
                        systemImage: "questionmark.circle",
                        description: Text("No profile with the id “\(fixture.profileID)” is in the library, so this fixture can't be controlled. Re-patch it to fix this.")
                    )
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(fixture.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ConnectionStatusView(compact: true)
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

    // MARK: - Sections

    @ViewBuilder
    private func intensitySection(_ profile: FixtureProfile, _ control: FixtureControl) -> some View {
        if control.supportsIntensity {
            Section {
                LevelFader(
                    title: "Level",
                    systemImage: "sun.max",
                    tint: .yellow,
                    value: control.intensityBinding
                )
                HStack {
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
                Text("Intensity")
            } footer: {
                Text(intensityExplanation(profile))
            }
        }
    }

    /// Says how this fixture actually dims, because on half a small rig it is
    /// not a dimmer channel and the difference shows up as surprising
    /// behaviour otherwise.
    private func intensityExplanation(_ profile: FixtureProfile) -> String {
        switch profile.intensityModel {
        case .dedicated:
            "Drives this fixture's dimmer channel."
        case let .band(channel, from, to, _):
            "“\(channel.name)” is one channel doing two jobs, so the level maps into its dimming band (\(from)–\(to)) instead of the full range."
        case .virtual:
            "This fixture has no dimmer, so the level scales the colour mix and keeps the hue."
        case .none:
            ""
        }
    }

    @ViewBuilder
    private func colorSection(_ profile: FixtureProfile, _ control: FixtureControl) -> some View {
        if profile.hasColorMixing {
            Section("Colour") {
                ColorPicker("Mix", selection: control.colorBinding, supportsOpacity: false)

                HStack(spacing: 8) {
                    ForEach(Self.quickColors, id: \.name) { swatch in
                        Button {
                            withAnimation(.snappy) { control.color = swatch.color }
                        } label: {
                            Circle()
                                .fill(swatch.color)
                                .frame(height: 30)
                                .overlay { Circle().strokeBorder(.separator) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(swatch.name)
                    }
                }

                ForEach(control.auxiliaryColorChannels) { channel in
                    ChannelFader(
                        title: channel.name,
                        subtitle: nil,
                        tint: channel.role.mixingTint,
                        value: control.binding(for: channel)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func positionSection(_ profile: FixtureProfile, _ control: FixtureControl) -> some View {
        if profile.hasMovement {
            Section("Position") {
                PositionPad(
                    pan: control.normalisedBinding(.pan),
                    tilt: control.normalisedBinding(.tilt),
                    panDegrees: profile.panDegrees,
                    tiltDegrees: profile.tiltDegrees
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

                LevelFader(title: "Pan", systemImage: "arrow.left.and.right", value: control.normalisedBinding(.pan))
                LevelFader(title: "Tilt", systemImage: "arrow.up.and.down", value: control.normalisedBinding(.tilt))

                if let speed = profile.channel(role: .movementSpeed) {
                    ChannelFader(
                        title: speed.name,
                        subtitle: "0 is fastest on most fixtures.",
                        value: control.binding(for: speed)
                    )
                }

                Button("Centre", systemImage: "scope") {
                    withAnimation(.snappy) {
                        control.setNormalised(0.5, for: .pan)
                        control.setNormalised(0.5, for: .tilt)
                    }
                }
            }
        }
    }

    /// Channels whose manual describes bands rather than a continuous sweep —
    /// shutter, gobo, colour macro, mode. A picker of named options beats a
    /// fader you have to land on the right value with.
    @ViewBuilder
    private func rangedSections(_ profile: FixtureProfile, _ control: FixtureControl) -> some View {
        let ranged = profile.channels.filter { !$0.ranges.isEmpty }
        if !ranged.isEmpty {
            Section("Settings") {
                ForEach(ranged) { channel in
                    RangedChannelRow(
                        channel: channel,
                        control: control,
                        onConfirmationNeeded: { range in
                            pendingConfirmation = PendingRange(channel: channel, range: range)
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func rawSection(_ profile: FixtureProfile, _ control: FixtureControl) -> some View {
        Section {
            DisclosureGroup("All \(profile.channelCount) channels", isExpanded: $showingRawChannels) {
                ForEach(profile.channels) { channel in
                    ChannelFader(
                        title: channel.name,
                        subtitle: address(of: channel, control),
                        tint: channel.role.mixingTint,
                        value: control.binding(for: channel)
                    )
                }
            }
        } header: {
            Text("Raw")
        } footer: {
            Text("Patched at \(fixture.startAddressValue), using \(profile.channelCount) channels.")
        }
    }

    private func actionsSection(_ control: FixtureControl) -> some View {
        Section {
            Button("Home", systemImage: "house") {
                withAnimation(.snappy) { control.home() }
            }
            Button("Reset to profile defaults", systemImage: "arrow.counterclockwise") {
                withAnimation(.snappy) { control.applyDefaults() }
            }
            Button("Zero", systemImage: "moon", role: .destructive) {
                withAnimation(.snappy) { control.zeroIntensity() }
            }
        }
    }

    private func address(of channel: FixtureChannel, _ control: FixtureControl) -> String? {
        control.address(of: channel).map { "DMX \($0.rawValue)" }
    }

    private static let quickColors: [(name: String, color: Color)] = [
        ("White", .white), ("Red", .red), ("Amber", .orange), ("Yellow", .yellow),
        ("Green", .green), ("Cyan", .cyan), ("Blue", .blue), ("Magenta", Color(red: 1, green: 0, blue: 1)),
    ]
}

/// A channel with named bands: a menu to choose one, and a fader scoped to the
/// band when the band is a continuous parameter like a strobe rate.
struct RangedChannelRow: View {
    let channel: FixtureChannel
    let control: FixtureControl
    let onConfirmationNeeded: (FixtureChannelRange) -> Void

    private var value: UInt8 { control.value(of: channel) }
    private var activeRange: FixtureChannelRange? { channel.range(containing: value) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(channel.name, systemImage: channel.role.symbolName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Menu {
                    ForEach(channel.ranges) { range in
                        Button {
                            if range.requiresConfirmation {
                                onConfirmationNeeded(range)
                            } else {
                                control.setValue(range.representativeValue, of: channel)
                            }
                        } label: {
                            Label(
                                range.label,
                                systemImage: range.requiresConfirmation ? "exclamationmark.triangle" : ""
                            )
                        }
                    }
                } label: {
                    Text(activeRange?.label ?? "Value \(Int(value))")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
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
            }
        }
    }
}
