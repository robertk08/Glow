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
		
		List {
			ForEach(monitor.blocks(owned: owned), id: \.first) { block in
				Section("\(block.first ?? 1)–\(block.last ?? 1)") {
					LazyVGrid(columns: columns, spacing: 4) {
						ForEach(block, id: \.self) { address in
							ChannelCell(address: address, monitor: monitor)
						}
					}
					.listRowInsets(.init(top: 12, leading: 12, bottom: 12, trailing: 12))
				}
			}
		}
		.listStyle(.insetGrouped)
		.navigationTitle("DMX Output")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .principal) {
				Picker("Values", selection: $monitor.showsSource) {
					Text("Output").tag(false)
					Text("Source").tag(true)
				}
				.pickerStyle(.segmented)
				.frame(width: 200)
			}
			
			ToolbarItem(placement: .topBarTrailing) {
				Toggle("Patched only", systemImage: "line.3.horizontal.decrease", isOn: $monitor.patchedOnly)
					.toggleStyle(.button)
			}
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
	let monitor: MonitorModel
	
	var body: some View {
		let value = monitor.values[address - 1]
		let isArmed = monitor.adjusting == address
		
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
		.background(alignment: .bottom) {
			ZStack(alignment: .bottom) {
				Rectangle()
					.fill(.fill.quaternary)
				
				Rectangle()
					.fill(Color.accentColor.opacity(0.55))
					.scaleEffect(y: Double(value) / 255, anchor: .bottom)
			}
		}
		.containerShape(.rect(cornerRadius: 10, style: .continuous))
		.clipShape(.rect(cornerRadius: 10, style: .continuous))
		.scaleEffect(isArmed ? 1.12 : 1)
		.animation(.snappy(duration: 0.15), value: isArmed)
		.simultaneousGesture(DragGesture(minimumDistance: 30).onChanged { drag in
			monitor.adjust(address, by: drag, console: console)
		}.onEnded { _ in
			monitor.commit()
		}, including: monitor.showsSource ? .all : .subviews)
		.accessibilityElement(children: .combine)
		.accessibilityValue("\(value)")
	}
}
