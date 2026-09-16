import SwiftData
import SwiftUI

struct LightsView: View {
    @Environment(Console.self) private var console
    @Environment(FixtureLibrary.self) private var library
    @Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]

    @State private var isAdding = false
    @State private var isShowingSettings = false

    var body: some View {
        @Bindable var console = console

        NavigationStack {
            List {
                if !fixtures.isEmpty {
                    Section {
                        Slider(value: $console.master, in: 0...1) {
                            Text("Brightness")
                        } minimumValueLabel: {
                            Image(systemName: "sun.min")
                        } maximumValueLabel: {
                            Image(systemName: "sun.max")
                        }

                        Toggle("Blackout", isOn: $console.blackout)
                    } header: {
                        Text("All Lights")
                    }
                }

                Section {
                    ForEach(fixtures) { fixture in
                        NavigationLink {
                            FixtureView(fixture: fixture)
                        } label: {
                            LightRow(fixture: fixture)
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
            .navigationTitle("Lights")
            .overlay {
                if fixtures.isEmpty {
                    ContentUnavailableView {
                        Label("No Lights", systemImage: "lightbulb")
                    } description: {
                        Text("Add the lights on your DMX line to control them.")
                    } actions: {
                        Button("Add Light") { isAdding = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") {
                        isShowingSettings = true
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add Light", systemImage: "plus") {
                        isAdding = true
                    }
                }
            }
            .sheet(isPresented: $isAdding) {
                AddLightView()
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .onChange(of: fixtures) { updateDimmers() }
            .task { updateDimmers() }
        }
    }

    private func control(_ fixture: Fixture) -> FixtureControl? {
        guard let profile = library.profile(fixture.profileID) else { return nil }
        return FixtureControl(profile: profile, start: fixture.start, console: console)
    }

    private func updateDimmers() {
        console.setDimmers(fixtures.flatMap { control($0)?.dimmers ?? [] })
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets {
            fixtures[index].modelContext?.delete(fixtures[index])
        }
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
