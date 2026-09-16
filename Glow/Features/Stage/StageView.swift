import SwiftData
import SwiftUI

/// The screen you actually run the rig from.
struct StageView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \PatchedFixture.sortIndex) private var fixtures: [PatchedFixture]

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 260), spacing: 16)]

    var body: some View {
        NavigationStack {
            Group {
                if fixtures.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
            .navigationTitle("Stage")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ConnectionStatusView(compact: true)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("All fixtures home", systemImage: "house") {
                        for fixture in fixtures {
                            model.control(for: fixture)?.home()
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                MasterBar()
            }
            .navigationDestination(for: PatchedFixture.self) { fixture in
                FixtureDetailView(fixture: fixture)
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(fixtures) { fixture in
                    NavigationLink(value: fixture) {
                        FixtureCard(fixture: fixture)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No fixtures patched", systemImage: "light.beacon.max")
        } description: {
            Text("Patch a fixture to start controlling it.")
        } actions: {
            NavigationLink("Open the library") {
                LibraryView()
            }
            .buttonStyle(.glassProminent)
        }
    }
}

/// One fixture at a glance: what it is, where it is, and what it is doing.
struct FixtureCard: View {
    @Environment(AppModel.self) private var model
    let fixture: PatchedFixture

    private var profile: FixtureProfile? { model.profile(for: fixture) }
    private var control: FixtureControl? { model.control(for: fixture) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: profile?.symbolName ?? "questionmark.circle")
                    .font(.headline)
                    .foregroundStyle(chipForeground)
                    .frame(width: 34, height: 34)
                    .background(swatch, in: .circle)
                    .overlay { Circle().strokeBorder(.separator) }
                Spacer()
                Text(addressLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(fixture.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let control, control.supportsIntensity {
                ProgressView(value: control.intensity)
                    .tint(swatch)
                    .accessibilityLabel("Intensity")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(profile == nil ? Color.red.opacity(0.6) : .clear)
        }
    }

    /// The colour the fixture is currently making, so the card reads as the
    /// light rather than as a row in a table.
    private var swatch: Color {
        guard let control, control.supportsColor else { return .accentColor }
        return control.color
    }

    /// A white fixture on a white card is invisible, so the glyph flips to
    /// dark once the colour behind it gets bright.
    private var chipForeground: Color {
        let components = swatch.rgbComponents
        let luminance = 0.2126 * components.red + 0.7152 * components.green + 0.0722 * components.blue
        return luminance > 0.6 ? .black : .white
    }

    private var subtitle: String {
        guard let profile else { return "Unknown profile" }
        return profile.mode.isEmpty ? "\(profile.channelCount) channels" : profile.mode
    }

    private var addressLabel: String {
        guard let profile else { return "\(fixture.startAddressValue)" }
        let range = Patch.range(of: fixture, profile: profile)
        return "\(range.lowerBound)–\(range.upperBound)"
    }
}

/// Grand master and blackout, always within reach.
struct MasterBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var engine = model.engine

        GlassEffectContainer(spacing: 16) {
            HStack(spacing: 16) {
                Button {
                    withAnimation(.snappy) { engine.blackout.toggle() }
                } label: {
                    Label(
                        engine.blackout ? "Blackout on" : "Blackout",
                        systemImage: engine.blackout ? "moon.fill" : "moon"
                    )
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(engine.blackout ? AnyPrimitiveButtonStyle(.glassProminent) : AnyPrimitiveButtonStyle(.glass))
                .tint(.red)
                .accessibilityLabel(engine.blackout ? "Turn blackout off" : "Blackout")

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Grand master")
                            .font(.caption.weight(.medium))
                        Spacer()
                        Text(engine.grandMaster, format: .percent.precision(.fractionLength(0)))
                            .font(.caption.monospacedDigit())
                            .contentTransition(.numericText(value: engine.grandMaster))
                    }
                    .foregroundStyle(.secondary)

                    Slider(value: $engine.grandMaster, in: 0...1) {
                        Text("Grand master")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(in: .rect(cornerRadius: 16))
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }
}

/// Lets a button style be chosen at runtime, which `buttonStyle(_:)` otherwise
/// will not allow because the two branches have different types.
struct AnyPrimitiveButtonStyle: PrimitiveButtonStyle {
    private let makeBodyClosure: @MainActor (Configuration) -> AnyView

    init(_ style: some PrimitiveButtonStyle) {
        makeBodyClosure = { configuration in
            AnyView(style.makeBody(configuration: configuration))
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        makeBodyClosure(configuration)
    }
}
