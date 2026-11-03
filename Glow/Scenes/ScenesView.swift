import SwiftData
import SwiftUI
import UniformTypeIdentifiers

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
	@State private var isEditing = false
	@State private var visible: CGFloat = 0
	@State private var position = ScrollPosition()
	@ScaledMetric(relativeTo: .headline) private var tileWidth = 168
	
	private var tiles: some View {
		let lists = Dictionary(CueList.all(looks, cues: cues, fixtures: fixtures).map { ($0.scene, $0) }, uniquingKeysWith: { first, _ in first })
		let shown = arrangement.arranged(looks)
		let tint = looks.first { $0.identifier == arrangement.lifted }?.tint.color ?? .accentColor
		
		return TileLayout(minimum: typeSize.isAccessibilitySize ? 300 : tileWidth, spacing: 12) {
			ForEach(shown) { look in
				SceneTile(look: look, list: lists[look.identifier, default: CueList(look, cues: [], fixtures: [])], arrangement: arrangement, isEditing: $isEditing, customizing: $customizing)
			}
		}
		.background(alignment: .topLeading) {
			if isEditing {
				ZStack(alignment: .topLeading) {
					ForEach(Array(arrangement.outlines(among: looks).enumerated()), id: \.offset) { _, outline in
						RoundedRectangle(cornerRadius: 24, style: .continuous)
							.strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
							.frame(width: outline.width, height: outline.height)
							.offset(x: outline.minX, y: outline.minY)
					}
					
					if let landing = arrangement.landing {
						RoundedRectangle(cornerRadius: 24, style: .continuous)
							.fill(tint.opacity(0.12))
							.strokeBorder(tint.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
							.frame(width: landing.width, height: landing.height)
							.offset(x: landing.minX, y: landing.minY)
					}
				}
			}
		}
		.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { arrangement.width = $0 }
		.padding(.bottom, isEditing ? (arrangement.row(among: looks) ?? 0) + 12 : 0)
		.onDrop(of: [.text], delegate: TileDrop(arrangement: arrangement, looks: looks))
		.coordinateSpace(.named("tiles"))
		.onChange(of: typeSize.isAccessibilitySize ? 300 : tileWidth, initial: true) { _, minimum in
			arrangement.minimum = minimum
		}
		.padding(.horizontal)
		.padding(.bottom, 24)
		.frame(minHeight: visible, alignment: .top)
		.background {
			if isEditing {
				Color.clear
					.contentShape(.rect)
					.onTapGesture {
						isEditing = false
					}
			}
		}
		.animation(.snappy(duration: 0.3), value: looks.map(\.slot))
		.animation(.snappy(duration: 0.3), value: isEditing)
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
					visible = geometry.containerSize.height
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
		.sensoryFeedback(.impact(weight: .light), trigger: arrangement.stretched != nil)
		.sensoryFeedback(.impact(weight: .light), trigger: arrangement.lifted != nil)
	}
}

private struct TileDrop: DropDelegate {
	let arrangement: Arrangement
	let looks: [Look]
	
	func validateDrop(info: DropInfo) -> Bool {
		arrangement.picked != nil
	}
	
	func dropUpdated(info: DropInfo) -> DropProposal? {
		if #unavailable(iOS 27) {
			arrangement.lift(among: looks)
			arrangement.drag(to: info.location)
		}
		
		return DropProposal(operation: .move)
	}
	
	func dropExited(info: DropInfo) {
		if #unavailable(iOS 27) { arrangement.leave() }
	}
	
	func performDrop(info: DropInfo) -> Bool {
		arrangement.drop(among: looks)
		return true
	}
}
