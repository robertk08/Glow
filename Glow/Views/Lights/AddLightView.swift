import SwiftData
import SwiftUI

struct AddLightView: View {
    @Environment(Console.self) private var console
    @Environment(FixtureLibrary.self) private var library
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]

    @State private var query = ""

    var body: some View {
        NavigationStack {
            List(library.search(query)) { profile in
                Button {
                    add(profile)
                    dismiss()
                } label: {
                    LabeledContent {
                        Text("\(profile.channelCount) ch")
                            .foregroundStyle(.secondary)
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text(profile.model)
                                if !profile.mode.isEmpty {
                                    Text(profile.mode)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: profile.symbol)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Add Light")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query)
            .toolbar {
                Button(role: .cancel) { dismiss() }
            }
        }
    }

    private func add(_ profile: FixtureProfile) {
        let address = nextFreeAddress(for: profile)
        let fixture = Fixture(
            profileID: profile.id,
            name: uniqueName(profile.model),
            address: address,
            sortIndex: (fixtures.map(\.sortIndex).max() ?? 0) + 1
        )
        context.insert(fixture)

        FixtureControl(profile: profile, start: address, console: console).applyDefaults()
    }

    private func nextFreeAddress(for profile: FixtureProfile) -> DMXAddress {
        let taken = fixtures
            .map { $0.range(library.profile($0.profileID)) }
            .sorted { $0.lowerBound < $1.lowerBound }

        var candidate = 1
        let width = max(1, profile.channelCount)

        for range in taken {
            if candidate + width - 1 < range.lowerBound { break }
            candidate = max(candidate, range.upperBound + 1)
        }

        return DMXAddress(candidate) ?? DMXAddress(1)!
    }

    private func uniqueName(_ base: String) -> String {
        let existing = Set(fixtures.map(\.name))
        guard existing.contains(base) else { return base }
        var index = 2
        while existing.contains("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
    }
}
