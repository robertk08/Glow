import SwiftData
import SwiftUI

struct MonitorView: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	@Query(sort: \Fixture.address) private var fixtures: [Fixture]
	
	@State private var monitor = MonitorModel()
	
	private let columns = [GridItem(.adaptive(minimum: 54, maximum: 74), spacing: 4)]
	
	var body: some View {
		let owned = monitor.owners(among: fixtures, library: library)
		
		return ScrollView {
			LazyVGrid(columns: columns, spacing: 4, pinnedViews: [.sectionHeaders]) {
				ForEach(monitor.blocks(owned: owned), id: \.first) { block in
					Section {
						ForEach(block, id: \.self) { address in
							ChannelCell(address: address, owned: owned.contains(address), monitor: monitor)
						}
					} header: {
						Text("\(block.first ?? 1)–\(block.last ?? 1)")
							.font(.caption.weight(.semibold))
							.foregroundStyle(.secondary)
							.frame(maxWidth: .infinity, alignment: .leading)
							.padding(.top, 8)
							.background(.background)
					}
				}
			}
			.padding(.horizontal)
			.padding(.bottom)
		}
		.scrollEdgeEffectStyle(.hard, for: .top)
		.navigationTitle("DMX Output")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			Toggle("Patched only", systemImage: "line.3.horizontal.decrease", isOn: $monitor.patchedOnly)
				.toggleStyle(.button)
		}
		.sensoryFeedback(.impact(flexibility: .rigid), trigger: monitor.adjusting)
		.task {
			monitor.watch(console)
		}
		.onDisappear {
			monitor.stop()
		}
	}
}

private struct ChannelCell: View {
	@Environment(Console.self) private var console
	
	let address: Int
	let owned: Bool
	let monitor: MonitorModel
	
	var body: some View {
		let value = monitor.values[address - 1]
		let isArmed = monitor.adjusting == address
		
		return VStack(spacing: 1) {
			Text("\(address)")
				.font(.system(size: 9).monospacedDigit())
				.foregroundStyle(.secondary)
			
			Text("\(value)")
				.font(.system(size: 13, weight: .medium).monospacedDigit())
				.contentTransition(.numericText(value: Double(value)))
		}
		.frame(maxWidth: .infinity)
		.padding(.vertical, 4)
		.background(alignment: .bottom) {
			ZStack(alignment: .bottom) {
				Rectangle()
					.fill(.fill.quaternary)
				
				Rectangle()
					.fill(owned ? Color.accentColor.opacity(0.55) : Color.orange.opacity(0.55))
					.scaleEffect(y: Double(value) / 255, anchor: .bottom)
			}
		}
		.containerShape(.rect(cornerRadius: 6, style: .continuous))
		.clipShape(.rect(cornerRadius: 6, style: .continuous))
		.scaleEffect(isArmed ? 1.12 : 1)
		.animation(.snappy(duration: 0.15), value: isArmed)
		.gesture(DragGesture(minimumDistance: 6).onChanged { drag in
			monitor.adjust(address, by: drag.translation, console: console)
		}.onEnded { _ in
			monitor.commit()
		})
	}
	
}
