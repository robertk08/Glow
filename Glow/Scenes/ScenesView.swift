import SwiftData
import SwiftUI

struct ScenesView: View {
	@Environment(Console.self) private var console
	@Environment(ShowLibrary.self) private var shows
	@Environment(\.modelContext) private var context
	@Environment(\.dynamicTypeSize) private var typeSize
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	@Query(sort: \Cue.sortIndex) private var cues: [Cue]
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	@State private var customizing: Look?
	@State private var isEditing = false
	@State private var arrangement = Arrangement()
	@State private var position = ScrollPosition()
	@ScaledMetric(relativeTo: .headline) private var tileWidth = 168
	
	private var tiles: some View {
		let lists = Dictionary(CueList.all(looks, cues: cues, fixtures: fixtures).map { ($0.scene, $0) }, uniquingKeysWith: { first, _ in first })
		let shown = arrangement.arranged(looks)
		
		return TileLayout(minimum: typeSize.isAccessibilitySize ? 300 : tileWidth, spacing: 12) {
			ForEach(shown) { look in
				SceneTile(look: look, list: lists[look.identifier, default: CueList(look, cues: [], fixtures: [])], arrangement: arrangement, isEditing: $isEditing, customizing: $customizing)
			}
		}
		.overlay(alignment: .topLeading) {
			if let look = looks.first(where: { $0.identifier == arrangement.lifted }), let floating = arrangement.floating {
				SceneFace(look: look, list: lists[look.identifier, default: CueList(look, cues: [], fixtures: [])])
					.frame(width: floating.width, height: floating.height)
					.scaleEffect(arrangement.isSettling ? 1 : 1.05)
					.shadow(color: .black.opacity(arrangement.isSettling ? 0 : 0.18), radius: 20, y: 10)
					.offset(x: floating.minX, y: floating.minY)
					.allowsHitTesting(false)
					.transition(.scale(scale: 1 / 1.05))
			}
		}
		.coordinateSpace(.named("tiles"))
		.padding(.horizontal)
		.padding(.bottom, 24)
		.animation(.snappy, value: looks.map(\.identifier))
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
				.scrollPosition($position)
				.onScrollGeometryChange(for: ScrollGeometry.self) { $0 } action: { _, geometry in
					arrangement.geometry = geometry
				}
				.task(id: arrangement.lifted) {
					while arrangement.lifted != nil, !Task.isCancelled {
						try? await Task.sleep(for: .milliseconds(16))
						
						if let offset = arrangement.autoscroll() {
							position.scrollTo(y: offset)
						}
					}
				}
			}
		}
		.navigationTitle("Scenes")
		.navigationSubtitle(isEditing ? "Drag to arrange, tap to customize" : shows.active.name)
		.toolbar {
			LinkStatusButton()
			
			ToolbarSpacer(.flexible, placement: .topBarTrailing)
			
			ToolbarItem(placement: .topBarTrailing) {
				if isPlaying {
					Button("All Off", systemImage: "stop.fill") {
						console.stopAll()
					}
					.buttonStyle(.glassProminent)
					.tint(.red)
				} else {
					Button("All Off", systemImage: "stop.fill") {
						console.stopAll()
					}
					.disabled(true)
				}
			}
			
			ToolbarSpacer(.fixed, placement: .topBarTrailing)
			
			if isEditing {
				ToolbarItem(placement: .topBarTrailing) {
					Button("Done", role: .confirm) {
						isEditing = false
					}
				}
			} else {
				ToolbarItem(placement: .topBarTrailing) {
					Button("Edit") {
						isEditing = true
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
		}
		.sheet(item: $customizing) { look in
			SceneSettings(look: look)
		}
		.sensoryFeedback(.selection, trigger: isEditing)
		.sensoryFeedback(.selection, trigger: arrangement.moves)
		.sensoryFeedback(.impact(weight: .light), trigger: arrangement.lifted != nil)
	}
}
