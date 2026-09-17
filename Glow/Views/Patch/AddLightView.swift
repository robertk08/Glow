import SwiftData
import SwiftUI

struct AddLightView: View {
    @Environment(FixtureLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var isBuilding = false

    private var results: [FixtureProfile] { library.search(query) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Build a Fixture", systemImage: "slider.horizontal.3") {
                        Haptic.feedback(.rigid)
                        isBuilding = true
                    }
                }

                Section {
                    ForEach(results) { profile in
                        NavigationLink {
                            PatchFixtureView(profile: profile)
                        } label: {
                            LabeledContent {
                                Text("\(profile.channelCount) ch")
                                    .foregroundStyle(.secondary)
                            } label: {
                                Label(profile.model, systemImage: profile.symbol)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Light")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query)
            .overlay {
                if results.isEmpty {
                    EmptyStateView(state: .search) {
                        Haptic.feedback(.rigid)
                        isBuilding = true
                    }
                }
            }
            .toolbar {
                Button(role: .close) { dismiss() }
            }
            .sheet(isPresented: $isBuilding) {
                CustomFixtureView()
            }
        }
    }
}

struct PatchFixtureView: View {
    @Environment(FixtureLibrary.self) private var library
    @Environment(Console.self) private var console
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]

    let profile: FixtureProfile

    @State private var name = ""
    @State private var count = 1
    @State private var address = 1
    @State private var hasChosenAddress = false

    private var width: Int { max(1, profile.channelCount) }
    private var lastAddress: Int { address + width * count - 1 }
    private var fits: Bool { lastAddress <= Universe.channelCount }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .autocorrectionDisabled()
            } footer: {
                Text("Leave empty to use the fixture's own name.")
            }

            Section {
                Stepper(value: $count, in: 1...64) {
                    LabeledContent("How many", value: "\(count)")
                }
            } footer: {
                if count > 1 {
                    Text("Each one gets the next free block of \(width) channels.")
                }
            }

            Section {
                Stepper(value: $address, in: DMXAddress.range) {
                    LabeledContent("Start address", value: "\(address)")
                }

                LabeledContent("Uses", value: count == 1 ? "\(address)–\(lastAddress)" : "\(address)–\(lastAddress), \(width) each")
            } header: {
                Text("Address")
            } footer: {
                if !fits {
                    Text("That runs past channel 512.")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Button("Add") { add() }
                    .disabled(!fits)
            }
        }
        .navigationTitle(profile.model)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !hasChosenAddress else { return }
            hasChosenAddress = true
            address = nextFree()
        }
    }

    private func add() {
        Haptic.feedback(.success)
        var next = address
        var index = (fixtures.map(\.sortIndex).max() ?? 0) + 1

        for number in 0..<count {
            guard let start = DMXAddress(next) else { break }
            let base = name.trimmingCharacters(in: .whitespaces).isEmpty ? profile.model : name
            let fixture = Fixture(
                profileID: profile.id,
                name: count == 1 ? uniqueName(base) : "\(base) \(number + 1)",
                address: start,
                sortIndex: index
            )
            context.insert(fixture)
            FixtureControl(profile: profile, start: start, console: console).applyDefaults()

            next += width
            index += 1
        }

        dismiss()
    }

    private func nextFree() -> Int {
        let taken = fixtures
            .map { $0.range(library.profile($0.profileID)) }
            .sorted { $0.lowerBound < $1.lowerBound }

        var candidate = 1
        for range in taken {
            if candidate + width - 1 < range.lowerBound { break }
            candidate = max(candidate, range.upperBound + 1)
        }
        return min(candidate, Universe.channelCount)
    }

    private func uniqueName(_ base: String) -> String {
        let existing = Set(fixtures.map(\.name))
        guard existing.contains(base) else { return base }
        var index = 2
        while existing.contains("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
    }
}
