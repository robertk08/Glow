import SwiftData
import SwiftUI

struct PatchView: View {
    @Environment(FixtureLibrary.self) private var library
    @Environment(\.modelContext) private var context
    @Query(sort: \Fixture.address) private var fixtures: [Fixture]
    
    @State private var isAdding = false
    
    private var used: Int {
        fixtures.reduce(0) { $0 + (library.profile($1.profileID)?.channelCount ?? 0) }
    }
    
    private var clashing: Set<PersistentIdentifier> {
        var found: Set<PersistentIdentifier> = []
        for (index, fixture) in fixtures.enumerated() {
            let range = fixture.range(library.profile(fixture.profileID))
            for other in fixtures.dropFirst(index + 1)
            where other.range(library.profile(other.profileID)).overlaps(range) {
                found.insert(fixture.persistentModelID)
                found.insert(other.persistentModelID)
            }
        }
        return found
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(fixtures) { fixture in
                        NavigationLink {
                            FixtureEditView(fixture: fixture)
                        } label: {
                            PatchRow(
                                fixture: fixture,
                                profile: library.profile(fixture.profileID),
                                clashes: clashing.contains(fixture.persistentModelID)
                            )
                        }
                        .swipeActions(edge: .leading) {
                            Button("Duplicate", systemImage: "plus.square.on.square") {
                                Haptic.feedback(.rigid)
                                let width = max(1, library.profile(fixture.profileID)?.channelCount ?? 1)
                                let copy = Fixture(profileID: fixture.profileID, name: fixture.name, address: DMXAddress(clamping: fixture.address + width), sortIndex: (fixtures.map(\.sortIndex).max() ?? 0) + 1)
                                copy.symbolOverride = fixture.symbolOverride
                                copy.tintName = fixture.tintName
                                context.insert(copy)
                            }
                            .tint(.accentColor)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            context.delete(fixtures[index])
                        }
                    }
                } footer: {
                    if !fixtures.isEmpty {
                        Text("\(used) of 512 channels used.")
                    }
                }
            }
            .navigationTitle("Patch")
            .overlay {
                if fixtures.isEmpty {
                    EmptyStateView(state: .patch) {
                        Haptic.feedback(.rigid)
                        isAdding = true
                    }
                }
            }
            .toolbar {
                Button("Add Light", systemImage: "plus") {
                    Haptic.feedback(.rigid)
                    isAdding = true
                }
            }
            .sheet(isPresented: $isAdding) {
                AddLightView()
            }
        }
    }
}

private struct PatchRow: View {
    let fixture: Fixture
    let profile: FixtureProfile?
    let clashes: Bool
    
    private var range: String {
        let span = fixture.range(profile)
        return span.lowerBound == span.upperBound
            ? "\(span.lowerBound)"
            : "\(span.lowerBound)–\(span.upperBound)"
    }
    
    var body: some View {
        LabeledContent {
            VStack(alignment: .trailing) {
                Text(range)
                    .monospacedDigit()
                
                if clashes {
                    Text("Overlaps")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        } label: {
            Label {
                VStack(alignment: .leading) {
                    Text(fixture.name)
                    Text(profile?.name ?? "Unknown fixture")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: fixture.symbol(profile))
            }
        }
    }
}
