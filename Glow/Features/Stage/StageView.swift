import SwiftData
import SwiftUI

/// The screen you run the rig from.
///
/// A split view at every width rather than a stack. On iPhone it collapses to
/// exactly the push navigation it had before; on iPad the rig sits beside the
/// fixture, which is the difference between a grand master stretched across
/// 1024pt of empty screen and a console.
struct StageView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \PatchedFixture.sortIndex) private var fixtures: [PatchedFixture]

    @State private var selectedID: PatchedFixture.ID?
    @State private var isConfirmingHomeAll = false
    @State private var isConfirmingZeroAll = false

    private var selected: PatchedFixture? {
        selectedID.flatMap { id in fixtures.first { $0.id == id } }
    }

    var body: some View {
        NavigationSplitView {
            rig
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 380)
        } detail: {
            NavigationStack {
                if let selected {
                    FixtureDetailView(fixture: selected)
                } else {
                    noSelection
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear(perform: reconcileSelection)
        .onChange(of: fixtures, reconcileSelection)
        .onChange(of: sizeClass) { reconcileSelection() }
    }

    // MARK: - Sidebar

    private var rig: some View {
        List(selection: $selectedID) {
            if fixtures.isEmpty {
                emptyState
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(fixtures) { fixture in
                        FixtureRow(fixture: fixture)
                            .tag(fixture.id)
                    }
                } header: {
                    Text(fixtures.count == 1 ? "1 fixture" : "\(fixtures.count) fixtures")
                }
            }
        }
        .navigationTitle("Stage")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                ConnectionStatusView(compact: true)
            }
            ToolbarItem(placement: .topBarTrailing) {
                rigMenu
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !fixtures.isEmpty {
                MasterBar()
            }
        }
        .confirmationDialog(
            "Home every fixture?",
            isPresented: $isConfirmingHomeAll,
            titleVisibility: .visible
        ) {
            Button("Home \(fixtures.count) fixtures", role: .destructive) {
                withAnimation(.snappy) {
                    for fixture in fixtures { model.control(for: fixture)?.home() }
                }
            }
        } message: {
            Text("Every fixture centres, opens its shutter and goes to full white. This replaces the look you have now and cannot be undone.")
        }
        .confirmationDialog(
            "Zero every level?",
            isPresented: $isConfirmingZeroAll,
            titleVisibility: .visible
        ) {
            Button("Zero \(fixtures.count) fixtures", role: .destructive) {
                withAnimation(.snappy) {
                    for fixture in fixtures { model.control(for: fixture)?.zeroIntensity() }
                }
            }
        } message: {
            Text("Takes every fixture's brightness to zero and keeps it there. To go dark for a moment instead, use Blackout — it is reversible.")
        }
    }

    private var rigMenu: some View {
        Menu {
            Section("Every fixture") {
                Button("Home all fixtures", systemImage: "scope") {
                    isConfirmingHomeAll = true
                }
                Button("Zero all levels", systemImage: "arrow.down.to.line") {
                    isConfirmingZeroAll = true
                }
            }
        } label: {
            Label("Rig actions", systemImage: "ellipsis.circle")
        }
        .disabled(fixtures.isEmpty)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No fixtures yet", systemImage: "light.beacon.max")
        } description: {
            Text("Add a light from the library and tell Glow which DMX address it is set to. Then it turns up here.")
        }
    }

    private var noSelection: some View {
        ContentUnavailableView {
            Label("No fixture selected", systemImage: "light.beacon.max")
        } description: {
            Text("Pick a light from the list to control it.")
        }
    }

    /// Keeps the detail column honest: fills it on iPad so the screen is never
    /// half empty, and drops a selection whose fixture has been unpatched.
    /// Never selects in compact width — there it would push the detail screen
    /// over the rig the moment you arrived.
    private func reconcileSelection() {
        if let selectedID, !fixtures.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
        }
        guard sizeClass == .regular, selectedID == nil else { return }
        selectedID = fixtures.first?.id
    }
}

/// One fixture in the rig list: what it is, where it is, what it is doing.
struct FixtureRow: View {
    @Environment(AppModel.self) private var model
    let fixture: PatchedFixture

    private var profile: FixtureProfile? { model.profile(for: fixture) }
    private var control: FixtureControl? { model.control(for: fixture) }

    var body: some View {
        HStack(spacing: 12) {
            chip

            VStack(alignment: .leading, spacing: 2) {
                Text(fixture.name)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(profile == nil ? Color.red : Color.secondary)
            }
            // The list is a column roughly 300pt wide on iPad. Wrapping every
            // row to three lines turns a rig of twenty into a long scroll for
            // text the detail pane is already showing in full.
            .lineLimit(1)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(addressLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let control, control.supportsIntensity {
                    Text(control.intensity, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.monospacedDigit().weight(.medium))
                        .contentTransition(.numericText(value: control.intensity))
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fixture.name)
        .accessibilityValue(accessibilityValue)
    }

    /// The fixture's own glyph on the colour it is currently making, ringed in
    /// its colour tag. Two colours on one chip, but they answer different
    /// questions: the fill is what the light is doing, the ring is which light
    /// it is, and the ring only appears once someone has tagged it.
    private var chip: some View {
        Image(systemName: fixture.symbolName(profile: profile))
            .font(.headline)
            .foregroundStyle(glyphColor)
            .frame(width: 38, height: 38)
            .background(outputColor, in: .circle)
            .overlay {
                if let tag = fixture.tint.color {
                    Circle().strokeBorder(tag, lineWidth: 2.5)
                } else {
                    // Heavier than a hairline separator on purpose: a fixture
                    // sitting at full white draws a white disc on a white row,
                    // and without this the chip disappears entirely.
                    Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1.5)
                }
            }
    }

    /// What the fixture is actually emitting, or nil when it emits no colour
    /// of its own.
    ///
    /// Via ``FixtureColorModel`` rather than ``FixtureControl/color``, which
    /// reads red/green/blue alone: an RGBWA head sitting on a warm white is
    /// mostly amber and white with barely any red, and through the RGB window
    /// that renders as near-black. The chip's whole job is to say what the
    /// light is doing, so it has to see every emitter.
    private var outputLight: LightColor? {
        guard let control, control.supportsColor else { return nil }
        return FixtureColorModel(control: control).renderedColor
    }

    /// A dimmer or a fog machine makes no colour, and filling its chip with
    /// the brand amber would claim it does.
    private var outputColor: Color {
        outputLight?.color ?? Color(.secondarySystemFill)
    }

    private var glyphColor: Color {
        outputLight?.contrastingInk ?? .accentColor
    }

    private var subtitle: String {
        guard let profile else { return "Profile missing — re-patch this fixture" }
        // A fixture is named after its model until someone renames it, so
        // repeating the model underneath would say nothing twice. Matched on
        // the model rather than the whole display name, which carries a
        // manufacturer the name never does.
        var parts: [String] = []
        if !fixture.name.localizedCaseInsensitiveContains(profile.model) {
            parts.append(profile.displayName)
        }
        if !profile.mode.isEmpty { parts.append(profile.mode) }
        return parts.isEmpty ? "\(profile.channelCount) channels" : parts.joined(separator: " · ")
    }

    private var addressLabel: String {
        guard let profile else { return "\(fixture.startAddressValue)" }
        let range = Patch.range(of: fixture, profile: profile)
        return "\(range.lowerBound)–\(range.upperBound)"
    }

    private var accessibilityValue: String {
        var parts = [subtitle, "address \(addressLabel)"]
        if let control, control.supportsIntensity {
            parts.append("\(Int((control.intensity * 100).rounded())) percent")
        }
        return parts.joined(separator: ", ")
    }
}

/// Grand master and blackout, always under your thumb.
///
/// Attached to the rig list rather than to the whole screen, so on iPad it is
/// the width of the list instead of the width of the window. The fixture
/// screen carries its own blackout in the navigation bar, which is what keeps
/// the kill switch reachable once this bar has scrolled out of the picture.
struct MasterBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var engine = model.engine

        GlassEffectContainer(spacing: 14) {
            VStack(spacing: 12) {
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
                    .accessibilityLabel("Grand master")
                    .accessibilityHint("Dims every fixture at once.")

                    if engine.blackout {
                        Text("Output is off. Your look is kept and comes back when you restore.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(in: .rect(cornerRadius: 18))

                BlackoutButton()
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .animation(.snappy, value: model.engine.blackout)
    }
}
