import SwiftData
import SwiftUI

@Model
final class Fixture {
    var profileID: String = ""
    var name: String = ""
    var address: Int = 1
    var sortIndex: Int = 0
    var symbolOverride: String?
    var tintName: String?
    var group: FixtureGroup?
    
    init(profileID: String, name: String, address: DMXAddress, sortIndex: Int) {
        self.profileID = profileID
        self.name = name
        self.address = address.value
        self.sortIndex = sortIndex
    }
    
    var start: DMXAddress {
        get { DMXAddress(clamping: address) }
        set { address = newValue.value }
    }
    
    var tint: FixtureTint {
        get { tintName.flatMap(FixtureTint.init(rawValue:)) ?? .none }
        set { tintName = newValue == .none ? nil : newValue.rawValue }
    }
    
    func symbol(_ profile: FixtureProfile?) -> String {
        symbolOverride ?? profile?.symbol ?? "lightbulb"
    }
    
    func range(_ profile: FixtureProfile?) -> ClosedRange<Int> {
        address...(address + max(1, profile?.channelCount ?? 1) - 1)
    }
    
    @MainActor static func firstFreeAddress(width: Int, among fixtures: [Fixture], library: FixtureLibrary) -> Int {
        var candidate = 1
        
        for range in fixtures.map({ $0.range(library.profile($0.profileID)) }).sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if candidate + width - 1 < range.lowerBound { break }
            candidate = max(candidate, range.upperBound + 1)
        }
        
        return min(candidate, Universe.channelCount)
    }
    
    static func unusedName(_ base: String, among fixtures: [Fixture]) -> String {
        let taken = Set(fixtures.map(\.name))
        guard taken.contains(base) else { return base }
        var index = 2
        
        while taken.contains("\(base) \(index)") {
            index += 1
        }
        
        return "\(base) \(index)"
    }
}

nonisolated enum FixtureSymbol {
    static let all = [
        "light.beacon.max", "light.panel", "lightbulb", "lightbulb.max", "light.strip.2",
        "light.max", "sun.max", "laser.burst", "sparkles", "star", "rays",
        "camera.aperture", "circle.hexagongrid", "smoke", "cloud.fog", "flame",
        "lamp.desk", "lamp.floor", "lamp.ceiling", "chandelier", "bolt", "waveform",
    ]
}

nonisolated enum FixtureTint: String, CaseIterable, Identifiable, Sendable {
    case none, red, orange, yellow, green, mint, teal, blue, indigo, purple, pink
    
    var id: String { rawValue }
    
    var color: Color? {
        switch self {
        case .none: nil
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        }
    }
}
