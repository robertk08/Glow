import SwiftData
import SwiftUI

struct FixtureView: View {
    @Environment(Console.self) private var console
    @Environment(FixtureLibrary.self) private var library

    @Bindable var fixture: Fixture

    @State private var confirming: ChannelRange?
    @State private var confirmingChannel: ProfileChannel?

    private var profile: FixtureProfile? { library.profile(fixture.profileID) }

    private var control: FixtureControl? {
        guard let profile else { return nil }
        return FixtureControl(profile: profile, start: fixture.start, console: console)
    }

    var body: some View {
        Form {
            if let profile, let control {
                if control.dims {
                    Section("Brightness") {
                        Slider(value: control.brightnessBinding, in: 0...1) {
                            Text("Brightness")
                        } minimumValueLabel: {
                            Image(systemName: "sun.min")
                        } maximumValueLabel: {
                            Image(systemName: "sun.max")
                        }
                    }
                }

                if profile.mixesColor {
                    ColorControl(control: control)
                }

                if profile.movesHead {
                    Section("Position") {
                        PositionPad(
                            pan: control.fractionBinding(.pan),
                            tilt: control.fractionBinding(.tilt)
                        )
                        .listRowInsets(EdgeInsets())

                        Button("Centre") {
                            control.setFraction(0.5, for: .pan)
                            control.setFraction(0.5, for: .tilt)
                        }
                    }
                }

                ForEach(settingsChannels(profile)) { channel in
                    Section(channel.name) {
                        Picker(channel.name, selection: bandSelection(control, channel)) {
                            ForEach(channel.ranges) { range in
                                Text(range.label).tag(range.id)
                            }
                        }
                        .labelsHidden()

                        if let active = channel.range(containing: control.value(of: channel)),
                           active.kind == .proportional {
                            Slider(
                                value: control.binding(channel),
                                in: Double(active.from)...Double(active.to),
                                step: 1
                            )
                        }
                    }
                }

                Section {
                    NavigationLink("All Channels") {
                        ChannelsView(control: control)
                    }

                    Button("Reset") {
                        control.home()
                    }
                }
            } else {
                Section {
                    ContentUnavailableView(
                        "Unknown Fixture",
                        systemImage: "questionmark.circle",
                        description: Text("Its profile is missing. Change it to control this light again.")
                    )
                }
            }
        }
        .navigationTitle(fixture.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            NavigationLink {
                FixtureEditView(fixture: fixture)
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
        }
        .alert("Reset the head?", isPresented: .constant(confirming != nil)) {
            Button("Cancel", role: .cancel) { clearConfirmation() }
            Button("Reset", role: .destructive) {
                if let confirming, let confirmingChannel, let control {
                    control.set(confirming.midpoint, of: confirmingChannel)
                }
                clearConfirmation()
            }
        } message: {
            Text("The light stops responding for a few seconds while it restarts.")
        }
    }

    private func settingsChannels(_ profile: FixtureProfile) -> [ProfileChannel] {
        profile.channels.filter { !$0.ranges.isEmpty && $0.role != .shutter }
    }

    private func bandSelection(_ control: FixtureControl, _ channel: ProfileChannel) -> Binding<String> {
        Binding(
            get: { channel.range(containing: control.value(of: channel))?.id ?? "" },
            set: { id in
                guard let range = channel.ranges.first(where: { $0.id == id }) else { return }
                if range.requiresConfirmation {
                    confirming = range
                    confirmingChannel = channel
                } else {
                    control.set(range.midpoint, of: channel)
                }
            }
        )
    }

    private func clearConfirmation() {
        confirming = nil
        confirmingChannel = nil
    }
}
