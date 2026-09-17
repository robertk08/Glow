import SwiftData
import SwiftUI

struct FixtureView: View {
    @Environment(Console.self) private var console
    @Environment(FixtureLibrary.self) private var library
    
    @Bindable var fixture: Fixture
    
    @State private var confirmingRange: ChannelRange?
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
                        PositionPad(pan: control.fractionBinding(.pan), tilt: control.fractionBinding(.tilt))
                            .listRowInsets(EdgeInsets())
                        
                        VStack(alignment: .leading) {
                            Text("Pan")
                            Slider(value: control.fractionBinding(.pan))
                        }
                        
                        VStack(alignment: .leading) {
                            Text("Tilt")
                            Slider(value: control.fractionBinding(.tilt))
                        }
                        
                        if let speed = profile.channel(.movementSpeed) {
                            VStack(alignment: .leading) {
                                Text(speed.name)
                                Slider(value: control.binding(speed), in: 0...255, step: 1)
                            }
                        }
                        
                        Button("Centre") {
                            Haptic.feedback(.rigid)
                            control.setFraction(0.5, for: .pan)
                            control.setFraction(0.5, for: .tilt)
                        }
                    }
                }
                
                ForEach(control.settings) { channel in
                    Section(channel.name) {
                        if channel.ranges.count > 1 {
                            Picker(channel.name, selection: Binding { channel.range(containing: control.value(of: channel))?.id ?? "" } set: { id in
                                guard let range = channel.ranges.first(where: { $0.id == id }) else { return }
                                
                                if range.requiresConfirmation {
                                    confirmingRange = range
                                    confirmingChannel = channel
                                } else {
                                    Haptic.feedback(.selection)
                                    control.set(range.midpoint, of: channel)
                                }
                            }) {
                                ForEach(channel.ranges) { range in
                                    Text(range.label).tag(range.id)
                                }
                            }
                            .labelsHidden()
                        }
                        
                        if let active = channel.range(containing: control.value(of: channel)), active.kind == .proportional {
                            Slider(value: control.binding(channel), in: Double(active.from)...Double(active.to), step: 1)
                        } else if channel.ranges.count <= 1 {
                            Slider(value: control.binding(channel), in: 0...255, step: 1)
                        }
                    }
                }
                
                Section {
                    NavigationLink("All Channels") {
                        ChannelsView(control: control)
                    }
                }
                
                Section {
                    Button("Bring Up") {
                        Haptic.feedback(.rigid)
                        control.home()
                    }
                    
                    Button("Reset to Defaults") {
                        Haptic.feedback(.rigid)
                        control.applyDefaults()
                    }
                } footer: {
                    Text("Bring Up centres the head, opens it and goes to white. Reset puts every channel back where the fixture profile says it starts.")
                }
            } else {
                Section {
                    ContentUnavailableView("Unknown Fixture", systemImage: "questionmark.circle", description: Text("Its profile is missing. Change it to control this light again."))
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
        .alert(confirmingRange?.label ?? "", isPresented: Binding { confirmingRange != nil } set: { _ in confirmingRange = nil }) {
            Button("Cancel", role: .cancel) {
                confirmingRange = nil
                confirmingChannel = nil
            }
            
            Button("Send", role: .destructive) {
                if let confirmingRange, let confirmingChannel, let control {
                    control.set(confirmingRange.midpoint, of: confirmingChannel)
                }
                
                confirmingRange = nil
                confirmingChannel = nil
            }
        } message: {
            Text("The light stops responding for a few seconds.")
        }
    }
}
