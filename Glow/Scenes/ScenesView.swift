import SwiftData
import SwiftUI

struct ScenesView: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	@Environment(ShowLibrary.self) private var shows
	@Environment(\.dynamicTypeSize) private var typeSize
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	@Query(sort: \Cue.sortIndex) private var cues: [Cue]
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	@State private var recording: Recording?
	@State private var showing: Look?
	@State private var isOrdering = false
	@ScaledMetric(relativeTo: .headline) private var tileWidth = 168
	
	private var columns: [GridItem] {
		[GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 300 : tileWidth), spacing: 12)]
	}
	
	@ViewBuilder private var tiles: some View {
		let lists = looks.map { CueList($0, cues: cues, fixtures: fixtures, library: library) }
		let items = ForEach(Array(zip(looks, lists)), id: \.0.identifier) { look, list in
			SceneTile(look: look, list: list, lists: lists, recording: $recording, showing: $showing)
		}
		let grid = LazyVGrid(columns: columns, spacing: 12) {
			if #available(iOS 27.0, *) {
				items.reorderable()
			} else {
				items
			}
		}
		.padding(.horizontal)
		
		if #available(iOS 27.0, *) {
			grid.reorderContainer(for: Look.self) { difference in
				console.move(difference, among: looks, sortIndex: \.sortIndex)
			}
		} else {
			grid
		}
	}
	
	var body: some View {
		Group {
			if looks.isEmpty {
				ContentUnavailableView {
					Label("No Scenes Yet", systemImage: "theatermasks")
				} description: {
					Text(fixtures.isEmpty ? "Patch a light first, set it how you want it, then store the look here." : "Set the lights how you want them, then store them as a scene. A tap turns it on and another turns it off again.")
				} actions: {
					Button("New Scene", systemImage: "plus") {
						recording = Recording(.scene, console: console, fixtures: fixtures, library: library, looks: looks, cues: cues)
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
				Button("Reorder", systemImage: "arrow.up.arrow.down") {
					isOrdering = true
				}
				.disabled(looks.count < 2)
			}
			
			ToolbarSpacer(.fixed, placement: .topBarTrailing)
			
			ToolbarItem(placement: .topBarTrailing) {
				Button("New Scene", systemImage: "plus") {
					recording = Recording(.scene, console: console, fixtures: fixtures, library: library, looks: looks, cues: cues)
				}
				.disabled(fixtures.isEmpty)
			}
		}
		.sheet(item: $recording) { recording in
			StoreView(recording: recording)
		}
		.sheet(item: $showing) { look in
			SceneView(look: look, isSheet: true)
				.presentationDetents([.medium, .large])
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
		.sensoryFeedback(.selection, trigger: console.playback)
	}
}

private struct SceneTile: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.modelContext) private var context
	@Environment(\.horizontalSizeClass) private var sizeClass
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	@Query(sort: \Cue.sortIndex) private var cues: [Cue]
	
	let look: Look
	let list: CueList
	let lists: [CueList]
	
	@Binding var recording: Recording?
	@Binding var showing: Look?
	
	@State private var isDeleting = false
	
	var body: some View {
		let index = list.index(of: console.playback.cue(of: look.identifier))
		let isOn = index != nil
		let tint = look.tint.color ?? .accentColor
		let isShown = sizeClass == .regular && console.selection.scene == look.identifier
		let current = index.flatMap { position in cues.first { $0.identifier == list.cues[position].identifier } }
		
		return VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 8) {
				Image(systemName: look.symbol)
					.font(.title3)
					.foregroundStyle(isOn ? Color.white : Color.secondary)
					.frame(width: 38, height: 38)
					.background(isOn ? tint : Color(.tertiarySystemFill), in: .circle)
				
				Spacer()
			}
			
			VStack(alignment: .leading, spacing: 1) {
				Text(look.name)
					.font(.headline)
					.lineLimit(1)
				
				Text(list.status(at: index))
					.font(.caption2)
					.foregroundStyle(.secondary)
					.monospacedDigit()
					.lineLimit(1)
			}
			
			Gauge(value: Double(index.map { $0 + 1 } ?? 0), in: 0...Double(max(1, list.cues.count))) {
				Text(look.name)
			}
			.gaugeStyle(.accessoryLinearCapacity)
			.tint(isOn ? tint : Color(.tertiarySystemFill))
			.labelsHidden()
			.padding(.vertical, 6)
		}
		.foregroundStyle(.primary)
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(14)
		.glassEffect(.regular.tint(isShown ? Color.accentColor.opacity(0.35) : nil).interactive(), in: .rect(cornerRadius: 24, style: .continuous))
		.contentShape(.rect(cornerRadius: 24, style: .continuous))
		.onTapGesture {
			console.selection.scene = look.identifier
			
			if list.cues.count > 1, isOn {
				console.go(list)
			} else {
				console.toggle(list, among: lists)
			}
		}
		.contentShape(.dragPreview, RoundedRectangle(cornerRadius: 24, style: .continuous))
		.accessibilityElement(children: .combine)
		.accessibilityAddTraits(.isButton)
		.accessibilityAddTraits(isOn ? .isSelected : [])
		.accessibilityHint(list.cues.count > 1 && isOn ? "Runs the next cue." : isOn ? "Turns the scene off." : "Turns the scene on.")
		.contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 24, style: .continuous))
		.contextMenu {
			if list.cues.count > 1, let index {
				Button("Next Cue", systemImage: "forward.end") {
					console.go(list)
				}
				.disabled(list.next(after: index) == nil)
				
				Button("Previous Cue", systemImage: "backward.end") {
					console.back(list)
				}
				.disabled(list.previous(before: index) == nil)
				
				Menu("Go to Cue", systemImage: "list.number") {
					ForEach(list.cues.indices, id: \.self) { position in
						Button("\(position + 1)  \(list.title(at: position))") {
							console.play(list, at: position)
						}
					}
				}
			}
			
			Button(isOn ? "Turn Off" : "Turn On", systemImage: isOn ? "stop.circle" : "play.circle") {
				console.toggle(list, among: lists)
			}
			
			Divider()
			
			Button("Cues", systemImage: "slider.horizontal.3") {
				console.selection.scene = look.identifier
				if sizeClass != .regular { showing = look }
			}
			
			Button("Add Cue", systemImage: "plus.rectangle.on.rectangle") {
				recording = Recording(.cue(look, after: current), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues)
			}
			
			if let current {
				Button("Store into Cue", systemImage: "square.and.arrow.down") {
					recording = Recording(.into(current), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues)
				}
			}
			
			Button("Duplicate", systemImage: "plus.square.on.square") {
				look.duplicate(with: cues, among: looks, context: context)
			}
			
			Button("Delete Scene", systemImage: "trash", role: .destructive) {
				isDeleting = true
			}
		}
		.confirmationDialog("Delete \(look.name)?", isPresented: $isDeleting, titleVisibility: .visible) {
			Button("Delete Scene", role: .destructive) {
				look.remove(with: cues, context: context)
			}
		} message: {
			Text("The lights stay as they are.")
		}
	}
}
