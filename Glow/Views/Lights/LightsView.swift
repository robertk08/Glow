import SwiftData
import SwiftUI

struct LightsView: View {
    @Environment(Console.self) private var console
    @Environment(FixtureLibrary.self) private var library
    @Environment(\.modelContext) private var context
    @Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
    @Query(sort: \FixtureGroup.sortIndex) private var groups: [FixtureGroup]

    @State private var isAdding = false
    @State private var newGroupName = ""
    @State private var isNamingGroup = false

    private var ungrouped: [Fixture] {
        fixtures.filter { $0.group == nil }
    }

    var body: some View {
        @Bindable var console = console

        NavigationStack {
            List {
                if !fixtures.isEmpty {
                    Section("All Lights") {
                        Slider(value: $console.master, in: 0...1) {
                            Text("Brightness")
                        } minimumValueLabel: {
                            Image(systemName: "sun.min")
                        } maximumValueLabel: {
                            Image(systemName: "sun.max")
                        }

                        Toggle("Blackout", isOn: $console.blackout)
                    }
                }

                if !groups.isEmpty {
                    Section("Groups") {
                        ForEach(groups) { group in
                            NavigationLink {
                                GroupView(group: group)
                            } label: {
                                GroupRow(group: group)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { context.delete(groups[index]) }
                        }
                    }
                }

                if !ungrouped.isEmpty {
                    Section(groups.isEmpty ? "" : "Other Lights") {
                        ForEach(ungrouped) { fixture in
                            NavigationLink {
                                FixtureView(fixture: fixture)
                            } label: {
                                LightRow(fixture: fixture)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Lights")
            .overlay {
                if fixtures.isEmpty {
                    EmptyStateView(state: .lights) {
                        Haptic.feedback(.rigid)
                        isAdding = true
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Add Light", systemImage: "plus") {
                            Haptic.feedback(.rigid)
                            isAdding = true
                        }

                        Button("New Group", systemImage: "square.stack.3d.up") {
                            Haptic.feedback(.rigid)
                            newGroupName = ""
                            isNamingGroup = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isAdding) {
                AddLightView()
            }
            .alert("New Group", isPresented: $isNamingGroup) {
                TextField("Name", text: $newGroupName)
                Button("Cancel", role: .cancel) {}
                Button("Create") { createGroup() }
            }
            .onChange(of: fixtures) { updateDimmers() }
            .task { updateDimmers() }
        }
    }

    private func createGroup() {
        let name = newGroupName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        context.insert(FixtureGroup(name: name, sortIndex: (groups.map(\.sortIndex).max() ?? 0) + 1))
    }

    private func control(_ fixture: Fixture) -> FixtureControl? {
        guard let profile = library.profile(fixture.profileID) else { return nil }
        return FixtureControl(profile: profile, start: fixture.start, console: console)
    }

    private func updateDimmers() {
        console.setDimmers(fixtures.flatMap { control($0)?.dimmers ?? [] })
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets { context.delete(ungrouped[index]) }
    }
}

struct LightRow: View {
    @Environment(Console.self) private var console
    @Environment(FixtureLibrary.self) private var library

    let fixture: Fixture

    private var profile: FixtureProfile? { library.profile(fixture.profileID) }

    private var control: FixtureControl? {
        guard let profile else { return nil }
        return FixtureControl(profile: profile, start: fixture.start, console: console)
    }

    private var iconColor: Color {
        if let tint = fixture.tint.color { return tint }
        guard let control, control.profile.mixesColor else { return .accentColor }
        return control.displayColor
    }

    var body: some View {
        LabeledContent {
            if let control, control.dims {
                Text(control.brightness, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } label: {
            Label {
                VStack(alignment: .leading) {
                    Text(fixture.name)
                    Text("Address \(fixture.address)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: fixture.symbol(profile))
                    .foregroundStyle(iconColor)
            }
        }
    }
}

struct GroupRow: View {
    let group: FixtureGroup

    var body: some View {
        LabeledContent {
            Text("\(group.members.count)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        } label: {
            Label {
                Text(group.name)
            } icon: {
                Image(systemName: group.symbol)
                    .foregroundStyle(group.tint.color ?? .accentColor)
            }
        }
    }
}
