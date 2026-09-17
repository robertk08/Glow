import SwiftUI

enum EmptyState {
    case lights, patch, groups, library, search, monitor

    var symbolName: String {
        switch self {
        case .lights: "lightbulb"
        case .patch: "list.number"
        case .groups: "square.stack.3d.up"
        case .library: "books.vertical"
        case .search: "magnifyingglass"
        case .monitor: "waveform"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .lights: "No Lights Yet"
        case .patch: "Nothing Patched"
        case .groups: "No Groups Yet"
        case .library: "No Fixtures"
        case .search: "Nothing Found"
        case .monitor: "No Output"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .lights: "Add the lights on your DMX line, then tap one to control it."
        case .patch: "Every light needs an address so the controller knows which part of the signal belongs to it."
        case .groups: "Put lights that belong together in a group and control them with one set of faders."
        case .library: "The bundled fixtures could not be loaded."
        case .search: "Try a different name, or build the fixture yourself."
        case .monitor: "Nothing is being sent yet. Patch a light and bring it up."
        }
    }

    var buttonLabel: Label<Text, Image> {
        switch self {
        case .lights, .patch: Label("Add Light", systemImage: "plus")
        case .groups: Label("New Group", systemImage: "plus")
        case .library: Label("Reload", systemImage: "arrow.clockwise")
        case .search: Label("Build a Fixture", systemImage: "slider.horizontal.3")
        case .monitor: Label("Add Light", systemImage: "plus")
        }
    }
}
