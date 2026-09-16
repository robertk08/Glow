import Foundation
import SwiftData

/// A fixture in the rig: a profile, an address, and a name.
///
/// Deliberately thin. It holds no channel values, because the values live in
/// the universe — a patched fixture is a *window* onto a span of addresses,
/// not a copy of them. That is what keeps the raw channel monitor and the
/// fixture controls from ever disagreeing.
@Model
final class PatchedFixture {
    /// Matches ``FixtureProfile/id``. Stored as a string rather than a
    /// relationship so a patch survives a profile being renamed or a library
    /// update, degrading to "unknown profile" instead of losing the fixture.
    var profileID: String = ""
    var name: String = ""
    var startAddressValue: Int = 1
    var sortIndex: Int = 0
    var createdAt: Date = Date.now

    init(profileID: String, name: String, startAddress: DMXAddress, sortIndex: Int = 0) {
        self.profileID = profileID
        self.name = name
        startAddressValue = startAddress.rawValue
        self.sortIndex = sortIndex
        createdAt = .now
    }

    var startAddress: DMXAddress {
        get { DMXAddress(clamping: startAddressValue) }
        set { startAddressValue = newValue.rawValue }
    }
}

/// Address arithmetic over a patch. A free function on a collection rather
/// than a stored model, so it is always derived from the current truth.
nonisolated enum Patch {
    /// The address span a fixture occupies.
    static func range(of fixture: PatchedFixture, profile: FixtureProfile?) -> ClosedRange<Int> {
        let count = max(1, profile?.channelCount ?? 1)
        let start = fixture.startAddressValue
        return start...(start + count - 1)
    }

    /// Pairs of fixtures whose channels overlap.
    ///
    /// Overlap is not rejected outright: rigs legitimately double-patch, and a
    /// console that refuses the edit is more annoying than one that flags it.
    static func conflicts(
        among fixtures: [PatchedFixture],
        profiles: (String) -> FixtureProfile?
    ) -> [(PatchedFixture, PatchedFixture)] {
        var found: [(PatchedFixture, PatchedFixture)] = []
        let sorted = fixtures.sorted { $0.startAddressValue < $1.startAddressValue }
        for (index, fixture) in sorted.enumerated() {
            let range = range(of: fixture, profile: profiles(fixture.profileID))
            for other in sorted.dropFirst(index + 1) {
                let otherRange = range_(other, profiles)
                if range.overlaps(otherRange) {
                    found.append((fixture, other))
                } else if otherRange.lowerBound > range.upperBound {
                    break
                }
            }
        }
        return found
    }

    private static func range_(
        _ fixture: PatchedFixture,
        _ profiles: (String) -> FixtureProfile?
    ) -> ClosedRange<Int> {
        range(of: fixture, profile: profiles(fixture.profileID))
    }

    /// The lowest address where `profile` fits without overlapping anything.
    static func nextFreeAddress(
        for profile: FixtureProfile,
        in fixtures: [PatchedFixture],
        profiles: (String) -> FixtureProfile?
    ) -> DMXAddress? {
        let occupied = fixtures
            .map { range_($0, profiles) }
            .sorted { $0.lowerBound < $1.lowerBound }

        let width = max(1, profile.channelCount)
        var candidate = 1

        for span in occupied {
            if candidate + width - 1 < span.lowerBound { break }
            candidate = max(candidate, span.upperBound + 1)
        }

        guard candidate + width - 1 <= DMXUniverse.channelCount else { return nil }
        return DMXAddress(rawValue: candidate)
    }
}
