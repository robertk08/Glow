import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(FixtureLibrary.self) private var library
    @Environment(\.modelContext) private var context
    @Query private var customProfiles: [CustomProfile]
    
    @State private var query = ""
    
    private var results: [FixtureProfile] { library.search(query) }
    
    var body: some View {
        List {
            if !customProfiles.isEmpty {
                Section("Built Here") {
                    ForEach(customProfiles) { custom in
                        NavigationLink {
                            ProfileView(profile: custom.profile)
                        } label: {
                            Label(custom.name, systemImage: custom.symbol)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { context.delete(customProfiles[index]) }
                    }
                }
            }
            
            Section {
                ForEach(library.bundled.filter { results.contains($0) }) { profile in
                    NavigationLink {
                        ProfileView(profile: profile)
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
        .navigationTitle("Fixtures")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query)
    }
}

struct ProfileView: View {
    let profile: FixtureProfile
    
    var body: some View {
        List {
            Section {
                if !profile.manufacturer.isEmpty {
                    LabeledContent("Make", value: profile.manufacturer)
                }
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
            
            ForEach(profile.channels) { channel in
                Section {
                    ForEach(channel.ranges) { range in
                        LabeledContent {
                            Text(range.label)
                                .multilineTextAlignment(.trailing)
                        } label: {
                            Text("\(range.from)–\(range.to)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                } header: {
                    HStack {
                        Text("\(channel.offset). \(channel.name)")
                        Spacer()
                        if channel.defaultValue != 0 {
                            Text("default \(channel.defaultValue)")
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .navigationTitle(profile.model)
        .navigationBarTitleDisplayMode(.inline)
    }
}
