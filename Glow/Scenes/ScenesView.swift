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
	@State private var isOrdering = false
	@State private var isEditing = false
	@State private var dragging: String?
	@ScaledMetric(relativeTo: .headline) private var tileWidth = 168
	
	private var tiles: some View {
		let lists = CueList.all(looks, cues: cues, fixtures: fixtures)
		
		return TileLayout(minimum: typeSize.isAccessibilitySize ? 300 : tileWidth, spacing: 12) {
			ForEach(Array(zip(looks, lists)), id: \.0.identifier) { look, list in
				SceneTile(look: look, list: list, isEditing: $isEditing, customizing: $customizing, dragging: $dragging)
			}
		}
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
						console.selection.building = Look.fresh(among: looks, context: context).identifier
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
					Button("Reorder", systemImage: "arrow.up.arrow.down") {
						isOrdering = true
					}
					.disabled(looks.count < 2)
				}
				
				ToolbarSpacer(.fixed, placement: .topBarTrailing)
				
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
							console.selection.building = Look.fresh(among: looks, context: context).identifier
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
		.sheet(isPresented: $isOrdering) {
			NavigationStack {
				List {
					ForEach(looks) { look in
						Label(look.name, systemImage: look.symbol)
					}
					.onMove { console.move($0, to: $1, among: looks, sortIndex: \.sortIndex) }
				}
				.environment(\.editMode, .constant(.active))
				.navigationTitle("Reorder")
				.navigationBarTitleDisplayMode(.inline)
				.toolbar {
					ToolbarItem(placement: .confirmationAction) {
						Button("Done") { isOrdering = false }
					}
				}
			}
		}
		.sensoryFeedback(.selection, trigger: isEditing)
	}
}
