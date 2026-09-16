import SwiftData
import SwiftUI

/// Every fixture type Glow knows how to drive.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    private var grouped: [(manufacturer: String, profiles: [FixtureProfile])] {
        let matches = model.library.profiles(matching: query)
        let owned = matches.filter(\.isOwned)
        let rest = Dictionary(grouping: matches.filter { !$0.isOwned }, by: \.manufacturer)
            .map { (manufacturer: $0.key, profiles: $0.value.sorted { $0.model < $1.model }) }
            .sorted { $0.manufacturer < $1.manufacturer }

        return owned.isEmpty ? rest : [("My rig", owned)] + rest
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(grouped, id: \.manufacturer) { group in
                    Section(group.manufacturer) {
                        ForEach(group.profiles) { profile in
                            NavigationLink {
                                ProfileDetailView(profile: profile)
                            } label: {
                                ProfileRow(profile: profile)
                            }
                        }
                    }
                }

                if !model.library.loadFailures.isEmpty {
                    Section("Profiles that failed to load") {
                        ForEach(model.library.loadFailures, id: \.self) { failure in
                            Text(failure)
                                .font(.caption.monospaced())
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .searchable(text: $query, prompt: "Fixtures")
            .overlay {
                if model.library.profiles.isEmpty {
                    ContentUnavailableView(
                        "No profiles",
                        systemImage: "books.vertical",
                        description: Text("The bundled fixture profiles could not be loaded.")
                    )
                } else if grouped.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
    }
}

struct ProfileRow: View {
    let profile: FixtureProfile

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: profile.symbolName)
                .frame(width: 28)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.model)
                Text(profile.mode.isEmpty ? "\(profile.channelCount) channels" : profile.mode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if profile.isOwned {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Your fixture")
            }
        }
    }
}

/// What a profile actually says: every channel, what it does, and which values
/// mean what.
struct ProfileDetailView: View {
    let profile: FixtureProfile

    var body: some View {
        List {
            Section {
                LabeledContent("Manufacturer", value: profile.manufacturer)
                LabeledContent("Model", value: profile.model)
                if !profile.mode.isEmpty {
                    LabeledContent("Mode", value: profile.mode)
                }
                LabeledContent("Channels", value: "\(profile.channelCount)")
                if let pan = profile.panDegrees {
                    LabeledContent("Pan", value: "\(Int(pan))°")
                }
                if let tilt = profile.tiltDegrees {
                    LabeledContent("Tilt", value: "\(Int(tilt))°")
                }
            }

            Section("Channels") {
                ForEach(profile.channels) { channel in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("\(channel.offset)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .trailing)
                            Label(channel.name, systemImage: channel.role.symbolName)
                                .font(.subheadline)
                            Spacer()
                            if channel.defaultValue != 0 {
                                Text("default \(channel.defaultValue)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }

                        ForEach(channel.ranges) { range in
                            HStack(spacing: 8) {
                                Text("\(range.from)–\(range.to)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 60, alignment: .leading)
                                Text(range.label).font(.caption)
                                if range.requiresConfirmation {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                            .padding(.leading, 30)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle(profile.model)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Choosing a profile to patch.
struct ProfilePickerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    let onSelect: (FixtureProfile) -> Void

    var body: some View {
        NavigationStack {
            List(model.library.profiles(matching: query)) { profile in
                Button {
                    onSelect(profile)
                    dismiss()
                } label: {
                    ProfileRow(profile: profile)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Add fixture")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Fixtures")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
