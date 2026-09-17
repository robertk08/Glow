import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(FixtureLibrary.self) private var library
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query private var customProfiles: [CustomProfile]

    @State private var section: Section? = .lights

    enum Section: String, CaseIterable, Identifiable {
        case lights, patch, monitor, settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .lights: "Lights"
            case .patch: "Patch"
            case .monitor: "Monitor"
            case .settings: "Settings"
            }
        }

        var symbol: String {
            switch self {
            case .lights: "lightbulb"
            case .patch: "list.number"
            case .monitor: "waveform"
            case .settings: "gearshape"
            }
        }
    }

    var body: some View {
        Group {
            if sizeClass == .compact {
                phone
            } else {
                pad
            }
        }
        .onChange(of: customProfiles) { syncCustomProfiles() }
        .task { syncCustomProfiles() }
    }

    private var phone: some View {
        TabView {
            Tab(Section.lights.title, systemImage: Section.lights.symbol) {
                LightsView()
            }

            Tab(Section.patch.title, systemImage: Section.patch.symbol) {
                PatchView()
            }

            Tab(Section.monitor.title, systemImage: Section.monitor.symbol) {
                MonitorView()
            }

            Tab(Section.settings.title, systemImage: Section.settings.symbol) {
                SettingsView()
            }
        }
    }

    private var pad: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $section) { item in
                Label(item.title, systemImage: item.symbol)
                    .tag(item)
            }
            .navigationTitle("Glow")
        } detail: {
            switch section {
            case .patch: PatchView()
            case .monitor: MonitorView()
            case .settings: SettingsView()
            case .lights, nil: LightsView()
            }
        }
    }

    private func syncCustomProfiles() {
        library.setCustom(customProfiles.map(\.profile))
    }
}
