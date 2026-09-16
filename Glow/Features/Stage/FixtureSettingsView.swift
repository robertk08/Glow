import SwiftData
import SwiftUI

/// Everything about one fixture that is not a live value: what it is called,
/// what it looks like in a list, and where it lives in the universe.
///
/// Reached from the fixture screen rather than only from Patch, because that
/// is where you are standing when you discover the name is wrong or the
/// address does not match the fixture's own display. Patch is for building a
/// rig; this is for fixing the one in front of you.
struct FixtureSettingsView: View {
    @Environment(AppModel.self) private var model
    @Bindable var fixture: PatchedFixture

    private var profile: FixtureProfile? { model.profile(for: fixture) }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Name", text: $fixture.name)
                    .autocorrectionDisabled()
            }

            Section {
                NavigationLink {
                    FixtureIconPicker(fixture: fixture, profile: profile)
                } label: {
                    LabeledContent("Icon") {
                        Image(systemName: fixture.symbolName(profile: profile))
                            .foregroundStyle(.secondary)
                    }
                }

                tintPicker
            } header: {
                Text("In the list")
            } footer: {
                Text("Two identical lights on opposite sides of a room are the same row twice. An icon and a colour tag are what tell them apart in the dark.")
            }

            Section {
                Stepper(value: $fixture.startAddressValue, in: 1...DMXUniverse.channelCount) {
                    LabeledContent("Start address") {
                        Text(fixture.startAddressValue, format: .number)
                            .monospacedDigit()
                    }
                }
                if let profile {
                    LabeledContent("Channels used", value: "\(profile.channelCount)")
                    LabeledContent("Range", value: {
                        let range = Patch.range(of: fixture, profile: profile)
                        return "\(range.lowerBound)–\(range.upperBound)"
                    }())
                }
            } header: {
                Text("Address")
            } footer: {
                Text("Set this to match the address shown on the fixture's own display. Get it wrong and the fixture ignores you, or answers to somebody else's channels.")
            }

            if let profile {
                Section {
                    LabeledContent("Fixture", value: profile.displayName)
                    if !profile.mode.isEmpty {
                        LabeledContent("Mode", value: profile.mode)
                    }
                    if let notes = profile.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Profile")
                } footer: {
                    Text("The profile decides what every channel means. To change it, re-patch this fixture from the library.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Fixture settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var tintPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Colour tag")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 10)], spacing: 10) {
                ForEach(FixtureTint.allCases) { tint in
                    Button {
                        fixture.tint = tint
                    } label: {
                        swatch(tint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tint.localizedName)
                    .accessibilityAddTraits(fixture.tint == tint ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func swatch(_ tint: FixtureTint) -> some View {
        ZStack {
            if let color = tint.color {
                Circle().fill(color)
            } else {
                Circle().fill(.quaternary)
                Image(systemName: "slash.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if fixture.tint == tint {
                Circle()
                    .strokeBorder(.primary, lineWidth: 2)
                    .padding(-4)
            }
        }
        .frame(width: 34, height: 34)
    }
}

/// A curated icon grid rather than the whole SF Symbols catalogue — see
/// ``FixtureIcon`` for why. Pushed rather than inline so the settings screen
/// stays one screenful.
struct FixtureIconPicker: View {
    @Bindable var fixture: PatchedFixture
    let profile: FixtureProfile?

    private let columns = [GridItem(.adaptive(minimum: 54), spacing: 12)]

    var body: some View {
        Form {
            Section {
                Button {
                    fixture.iconName = nil
                } label: {
                    HStack {
                        Image(systemName: profile?.symbolName ?? FixtureIcon.fallback)
                            .frame(width: 28)
                        Text("Whatever the profile says")
                        Spacer()
                        if fixture.iconName == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(fixture.iconName == nil ? [.isButton, .isSelected] : .isButton)
            } footer: {
                Text("Pick one below only when a rig has two of the same thing in it.")
            }

            ForEach(FixtureIcon.groups) { group in
                Section(group.name) {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(group.symbols, id: \.self) { symbol in
                            iconButton(symbol)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Icon")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func iconButton(_ symbol: String) -> some View {
        let isSelected = fixture.iconName == symbol
        return Button {
            fixture.iconName = symbol
        } label: {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .frame(width: 48, height: 48)
                .background(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
