import SwiftData
import SwiftUI

struct MonitorView: View {
    @Environment(Console.self) private var console
    @Environment(FixtureLibrary.self) private var library
    @Query(sort: \Fixture.address) private var fixtures: [Fixture]
    
    @State private var patchedOnly = false
    @State private var isAdding = false
    
    private let columns = [GridItem(.adaptive(minimum: 54, maximum: 74), spacing: 4)]
    
    private var owners: [Int: String] {
        var map: [Int: String] = [:]
        for fixture in fixtures {
            for address in fixture.range(library.profile(fixture.profileID)) {
                map[address] = fixture.name
            }
        }
        return map
    }
    
    private var addresses: [Int] {
        let all = Array(DMXAddress.range)
        guard patchedOnly else { return all }
        let owned = owners
        return all.filter { owned[$0] != nil }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if fixtures.isEmpty {
                    EmptyStateView(state: .monitor) {
                        Haptic.feedback(.rigid)
                        isAdding = true
                    }
                } else {
                    grid
                }
            }
            .navigationTitle("Monitor")
            .toolbar {
                if !fixtures.isEmpty {
                    Toggle("Patched only", systemImage: "line.3.horizontal.decrease", isOn: $patchedOnly)
                        .toggleStyle(.button)
                }
            }
            .sheet(isPresented: $isAdding) {
                AddLightView(isPresented: $isAdding)
            }
        }
    }
    
    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(addresses, id: \.self) { address in
                    ChannelCell(
                        address: address,
                        value: console.universe.values[address - 1],
                        owned: owners[address] != nil
                    )
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }
}

private struct ChannelCell: View {
    let address: Int
    let value: UInt8
    let owned: Bool
    
    var body: some View {
        VStack(spacing: 1) {
            Text("\(address)")
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.secondary)
            
            Text("\(value)")
                .font(.system(size: 13, weight: .medium).monospacedDigit())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(background, in: .rect(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(owned ? Color.accentColor.opacity(0.4) : .clear)
        }
    }
    
    private var background: some ShapeStyle {
        value == 0
            ? AnyShapeStyle(.fill.quaternary)
            : AnyShapeStyle(Color.accentColor.opacity(0.15 + 0.5 * Double(value) / 255))
    }
}
