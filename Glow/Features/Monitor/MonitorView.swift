import SwiftData
import SwiftUI

/// Every one of the 512 channels, live.
///
/// This is the screen that answers "is the app sending what I think it is
/// sending", which is the first question worth asking when a fixture does
/// something inexplicable.
struct MonitorView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \PatchedFixture.sortIndex) private var fixtures: [PatchedFixture]

    @State private var showsOnlyPatched = false

    private let columns = [GridItem(.adaptive(minimum: 52, maximum: 72), spacing: 4)]

    /// Which fixture, if any, owns each address.
    private var ownership: [Int: String] {
        var map: [Int: String] = [:]
        for fixture in fixtures {
            guard let profile = model.profile(for: fixture) else { continue }
            for address in Patch.range(of: fixture, profile: profile) {
                map[address] = fixture.name
            }
        }
        return map
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(visibleAddresses, id: \.self) { address in
                        ChannelCell(
                            address: address,
                            value: model.engine.universe.values[address - 1],
                            owner: ownership[address]
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Monitor")
            // Inline, because the summary bar is pinned directly beneath the
            // navigation bar and a large title leaves a band of empty grey
            // between the two.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle("Patched only", systemImage: "line.3.horizontal.decrease.circle", isOn: $showsOnlyPatched)
                        .toggleStyle(.button)
                }
                ToolbarItem(placement: .topBarLeading) {
                    ConnectionStatusView(compact: true)
                }
            }
            .safeAreaInset(edge: .top) {
                summary
            }
        }
    }

    private var visibleAddresses: [Int] {
        let all = Array(1...DMXUniverse.channelCount)
        guard showsOnlyPatched else { return all }
        let owned = ownership
        return all.filter { owned[$0] != nil }
    }

    private var summary: some View {
        HStack(spacing: 16) {
            Label("\(activeCount) active", systemImage: "bolt.fill")
            Label("\(ownership.count) patched", systemImage: "list.number")
            Spacer()
            Text("\(model.engine.refreshRate) Hz")
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var activeCount: Int {
        model.engine.universe.values.count { $0 > 0 }
    }
}

struct ChannelCell: View {
    let address: Int
    let value: UInt8
    let owner: String?

    var body: some View {
        VStack(spacing: 1) {
            Text("\(address)")
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .contentTransition(.numericText(value: Double(value)))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(background, in: .rect(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(owner == nil ? .clear : Color.accentColor.opacity(0.4))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Channel \(address)\(owner.map { ", \($0)" } ?? "")")
        .accessibilityValue("\(value)")
    }

    /// Brightness of the cell tracks the channel value, so a glance at the
    /// grid reads as a picture of the output rather than a wall of numbers.
    private var background: some ShapeStyle {
        value == 0
            ? AnyShapeStyle(.background.secondary)
            : AnyShapeStyle(Color.accentColor.opacity(0.15 + 0.5 * Double(value) / 255))
    }
}
