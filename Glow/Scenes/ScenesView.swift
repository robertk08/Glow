import SwiftData
import SwiftUI

struct ScenesView: View {
	@Environment(Console.self) private var console
	@Environment(ShowLibrary.self) private var shows
	@Environment(\.modelContext) private var context
	@Environment(\.dynamicTypeSize) private var typeSize
	@Environment(Arrangement.self) private var arrangement
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	@Query(sort: \Cue.sortIndex) private var cues: [Cue]
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	@State private var customizing: Look?
	@State private var isArranging = false
	@ScaledMetric(relativeTo: .headline) private var tileWidth = 168
	
	private var tiles: some View {
		let lists = Dictionary(CueList.all(looks, cues: cues, fixtures: fixtures).map { ($0.scene, $0) }, uniquingKeysWith: { first, _ in first })
		
		return TileLayout(minimum: typeSize.isAccessibilitySize ? 300 : tileWidth, spacing: 12) {
			ForEach(looks) { look in
				SceneTile(look: look, list: lists[look.identifier, default: CueList(look, cues: [], fixtures: [])], arrangement: arrangement, isArranging: $isArranging, customizing: $customizing)
			}
		}
		.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { arrangement.width = $0 }
		.coordinateSpace(.named("tiles"))
		.onChange(of: typeSize.isAccessibilitySize ? 300 : tileWidth, initial: true) { _, minimum in
			arrangement.minimum = minimum
		}
		.padding(.horizontal)
		.padding(.bottom, 24)
		.animation(.snappy(duration: 0.3), value: looks.map(\.slot))
		.animation(.snappy(duration: 0.3), value: looks.map(\.size))
	}
	
	var body: some View {
		let isPlaying = console.playback.playing.contains { entry in looks.contains { $0.identifier == entry.scene } }
		
		Group {
			if looks.isEmpty {
				ContentUnavailableView {
					Label("No Scenes Yet", systemImage: "theatermasks")
				} description: {
					if fixtures.isEmpty {
						Text("Patch a light first.")
					} else {
						Text("Store what the lights are doing and bring it back with one tap.")
					}
				} actions: {
					Button("New Scene", systemImage: "plus") {
						console.selection.build(Look.fresh(among: looks, context: context).identifier, isNew: true)
					}
					.font(.headline)
					.buttonStyle(.glassProminent)
					.controlSize(.large)
					.disabled(fixtures.isEmpty)
				}
			} else {
				ScrollView {
					tiles
				}
			}
		}
		.navigationTitle("Scenes")
		.navigationSubtitle(shows.active.name)
		.toolbar {
			LinkStatusButton()
			
			ToolbarSpacer(.flexible, placement: .topBarTrailing)
			
			if isPlaying {
				ToolbarItem(placement: .topBarTrailing) {
					Button("All Off", systemImage: "stop.fill") {
						console.stopAll()
					}
					.buttonStyle(.glassProminent)
					.tint(.red)
				}
				
				ToolbarSpacer(.fixed, placement: .topBarTrailing)
			}
			
			ToolbarItem(placement: .topBarTrailing) {
				Button("Edit") {
					isArranging = true
				}
				.disabled(looks.isEmpty)
			}
			
			ToolbarSpacer(.fixed, placement: .topBarTrailing)
			
			ToolbarItem(placement: .topBarTrailing) {
				Button("New Scene", systemImage: "plus") {
					if console.selection.building == nil {
						console.selection.build(Look.fresh(among: looks, context: context).identifier, isNew: true)
					} else {
						console.selection.section = "lights"
					}
				}
				.disabled(fixtures.isEmpty)
			}
		}
		.sheet(item: $customizing) { look in
			SceneSettings(look: look)
		}
		.sheet(isPresented: $isArranging) {
			ArrangeView(columns: arrangement.columns)
		}
	}
}
