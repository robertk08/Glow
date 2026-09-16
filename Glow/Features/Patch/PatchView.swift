import SwiftData
import SwiftUI

/// The rig: what is patched, where, and whether any of it collides.
struct PatchView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \PatchedFixture.sortIndex) private var fixtures: [PatchedFixture]

    @State private var isPickingProfile = false

    private var conflicts: [(PatchedFixture, PatchedFixture)] {
        Patch.conflicts(among: fixtures) { model.library.profile(id: $0) }
    }

    private var conflictingIDs: Set<PersistentIdentifier> {
        Set(conflicts.flatMap { [$0.0.persistentModelID, $0.1.persistentModelID] })
    }

    var body: some View {
        NavigationStack {
            List {
                if !conflicts.isEmpty {
                    Section {
                        Label(
                            "^[\(conflicts.count) fixture](inflect: true) overlap another fixture's channels. They will respond together.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                        .font(.footnote)
                    }
                }

                Section {
                    ForEach(fixtures) { fixture in
                        NavigationLink {
                            PatchDetailView(fixture: fixture)
                        } label: {
                            PatchRow(
                                fixture: fixture,
                                profile: model.profile(for: fixture),
                                hasConflict: conflictingIDs.contains(fixture.persistentModelID)
                            )
                        }
                    }
                    .onDelete(perform: delete)
                    .onMove(perform: move)
                } footer: {
                    if !fixtures.isEmpty {
                        Text("\(usedChannels) of 512 channels used.")
                    }
                }
            }
            .navigationTitle("Patch")
            .overlay {
                if fixtures.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing patched", systemImage: "list.number")
                    } description: {
                        Text("Add a fixture to tell Glow what is plugged into the DMX line and at which address.")
                    } actions: {
                        Button("Add fixture") { isPickingProfile = true }
                            .buttonStyle(.glassProminent)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add fixture", systemImage: "plus") { isPickingProfile = true }
                }
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
            .sheet(isPresented: $isPickingProfile) {
                ProfilePickerSheet { profile in
                    patch(profile)
                }
            }
        }
    }

    private var usedChannels: Int {
        fixtures.reduce(0) { total, fixture in
            total + (model.profile(for: fixture)?.channelCount ?? 0)
        }
    }

    private func patch(_ profile: FixtureProfile) {
        let address = Patch.nextFreeAddress(for: profile, in: fixtures) {
            model.library.profile(id: $0)
        } ?? .first

        let fixture = PatchedFixture(
            profileID: profile.id,
            name: uniqueName(for: profile),
            startAddress: address,
            sortIndex: (fixtures.map(\.sortIndex).max() ?? 0) + 1
        )
        context.insert(fixture)

        // Give it the profile's defaults straight away, so a fixture that has
        // just been patched responds instead of sitting dark behind a mode
        // channel nobody has thought about yet.
        FixtureControl(profile: profile, startAddress: address, engine: model.engine)
            .applyDefaults()
    }

    private func uniqueName(for profile: FixtureProfile) -> String {
        let base = profile.model
        let existing = Set(fixtures.map(\.name))
        guard existing.contains(base) else { return base }
        var index = 2
        while existing.contains("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(fixtures[index])
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = fixtures
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, fixture) in reordered.enumerated() {
            fixture.sortIndex = index
        }
    }
}

struct PatchRow: View {
    let fixture: PatchedFixture
    let profile: FixtureProfile?
    let hasConflict: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: profile?.symbolName ?? "questionmark.circle")
                .frame(width: 28)
                .foregroundStyle(profile == nil ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))

            VStack(alignment: .leading, spacing: 2) {
                Text(fixture.name)
                Text(profile?.displayName ?? "Unknown profile")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(addressLabel)
                    .font(.subheadline.monospacedDigit())
                if hasConflict {
                    Label("Overlap", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .labelStyle(.titleAndIcon)
                }
            }
        }
    }

    private var addressLabel: String {
        guard let profile else { return "\(fixture.startAddressValue)" }
        let range = Patch.range(of: fixture, profile: profile)
        return "\(range.lowerBound)–\(range.upperBound)"
    }
}

/// Renaming and re-addressing one patched fixture.
struct PatchDetailView: View {
    @Environment(AppModel.self) private var model
    @Bindable var fixture: PatchedFixture

    private var profile: FixtureProfile? { model.profile(for: fixture) }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Name", text: $fixture.name)
            }

            Section {
                Stepper(value: $fixture.startAddressValue, in: 1...DMXUniverse.channelCount) {
                    LabeledContent("Start address") {
                        Text(fixture.startAddressValue, format: .number)
                            .monospacedDigit()
                    }
                }
                if let profile {
                    LabeledContent("Channels", value: "\(profile.channelCount)")
                    LabeledContent("Range", value: {
                        let range = Patch.range(of: fixture, profile: profile)
                        return "\(range.lowerBound)–\(range.upperBound)"
                    }())
                }
            } header: {
                Text("Address")
            } footer: {
                Text("Set this to match the address on the fixture's own display.")
            }

            if let profile {
                Section("Profile") {
                    LabeledContent("Fixture", value: profile.displayName)
                    if !profile.mode.isEmpty {
                        LabeledContent("Mode", value: profile.mode)
                    }
                    NavigationLink("Channel layout") {
                        ProfileDetailView(profile: profile)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(fixture.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
