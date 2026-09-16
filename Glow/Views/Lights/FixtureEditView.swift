import SwiftData
import SwiftUI

struct FixtureEditView: View {
    @Environment(FixtureLibrary.self) private var library
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]

    @Bindable var fixture: Fixture

    private var profile: FixtureProfile? { library.profile(fixture.profileID) }

    private var overlapping: [Fixture] {
        let range = fixture.range(profile)
        return fixtures.filter {
            $0.persistentModelID != fixture.persistentModelID
                && $0.range(library.profile($0.profileID)).overlaps(range)
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 12)]

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $fixture.name)
            }

            Section("Icon") {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(FixtureSymbol.all, id: \.self) { symbol in
                        Button {
                            fixture.symbolOverride = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.title3)
                                .frame(width: 44, height: 44)
                                .background(
                                    fixture.symbol(profile) == symbol ? Color.accentColor.opacity(0.2) : .clear,
                                    in: .circle
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)

                Picker("Colour", selection: $fixture.tint) {
                    ForEach(FixtureTint.allCases) { tint in
                        Text(tint.rawValue.capitalized).tag(tint)
                    }
                }
            }

            Section {
                Stepper(value: $fixture.address, in: DMXAddress.range) {
                    LabeledContent("Address", value: "\(fixture.address)")
                }

                if let profile {
                    LabeledContent("Channels", value: "\(profile.channelCount)")
                    LabeledContent("Fixture", value: profile.name)
                }
            } footer: {
                if !overlapping.isEmpty {
                    Text("Shares channels with \(overlapping.map(\.name).formatted(.list(type: .and))). They will move together.")
                }
            }

            Section {
                Button("Remove Light", role: .destructive) {
                    context.delete(fixture)
                    dismiss()
                }
            }
        }
        .navigationTitle(fixture.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
