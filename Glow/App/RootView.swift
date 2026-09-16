import SwiftData
import SwiftUI

/// The tabs, and nothing else.
///
/// Before adding a screen, read ``DetailLevel``. It holds the rule the whole
/// app follows for serving a first-time user and a lighting operator from the
/// same layout, and a screen that ignores it is the one that makes the app
/// feel like two apps.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \PatchedFixture.sortIndex) private var fixtures: [PatchedFixture]
    @State private var selection: Section = .stage

    enum Section: Hashable {
        case stage, patch, library, monitor, settings
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Stage", systemImage: "light.beacon.max", value: Section.stage) {
                StageView()
            }
            Tab("Patch", systemImage: "list.number", value: Section.patch) {
                PatchView()
            }
            Tab("Library", systemImage: "books.vertical", value: Section.library) {
                LibraryView()
            }
            Tab("Monitor", systemImage: "waveform.path", value: Section.monitor) {
                MonitorView()
            }
            Tab("Settings", systemImage: "gearshape", value: Section.settings) {
                SettingsView()
            }
        }
        // Sidebar on iPad and in wide windows, a tab bar on iPhone, from one
        // declaration — and on iPadOS 26 the sidebar is what makes the app
        // usable at arbitrary window sizes.
        .tabViewStyle(.sidebarAdaptable)
        .onChange(of: fixtures) { model.patchDidChange(fixtures) }
        .task { model.patchDidChange(fixtures) }
    }
}
