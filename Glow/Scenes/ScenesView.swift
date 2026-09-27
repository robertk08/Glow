import SwiftData
import SwiftUI

struct ScenesView: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	@Environment(ShowLibrary.self) private var shows
	@Environment(\.modelContext) private var context
	@Environment(\.dynamicTypeSize) private var typeSize
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	@Query(sort: \Cue.sortIndex) private var cues: [Cue]
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	@State private var recording: Recording?
	@State private var showing: Look?
	@State private var deleting: Look?
	@State private var isOrdering = false
	@ScaledMetric(relativeTo: .headline) private var tileWidth = 320
	
	private var columns: [GridItem] {
		[GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 600 : tileWidth), spacing: 12)]
	}
	
	@ViewBuilder private var tiles: some View {
		let lists = looks.map { CueList($0, cues: cues, fixtures: fixtures, library: library) }
		let items = ForEach(Array(zip(looks, lists)), id: \.0.identifier) { look, list in
			SceneTile(look: look, list: list, lists: lists, recording: $recording, showing: $showing, deleting: $deleting)
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
		.confirmationDialog("Delete \(deleting?.name ?? "Scene")?", isPresented: Binding { deleting != nil } set: { _ in deleting = nil }, titleVisibility: .visible, presenting: deleting) { look in
			Button("Delete Scene", role: .destructive) {
				look.remove(with: cues, context: context)
			}
		} message: { _ in
			Text("The lights stay as they are.")
		}
	}
}

private struct SceneTile: View {
	@Environment(Console.self) private var console
	@Environment(\.horizontalSizeClass) private var sizeClass
	
	let look: Look
	let list: CueList
	let lists: [CueList]
	
	@Binding var recording: Recording?
	@Binding var showing: Look?
	@Binding var deleting: Look?
	
	var body: some View {
		let index = list.index(of: console.playback.cue(of: look.identifier))
		let isOn = index != nil
		let hasCues = list.cues.count > 1
		let tint = look.tint.color ?? .accentColor
		let isShown = sizeClass == .regular && console.selection.scene == look.identifier
		
		return VStack(alignment: .leading, spacing: 14) {
			HStack(alignment: .top, spacing: 10) {
				Button {
					console.selection.scene = look.identifier
					console.run(look.tap, on: list, among: lists)
				} label: {
					HStack(spacing: 14) {
						Image(systemName: look.symbol)
							.font(.title2)
							.foregroundStyle(isOn ? Color.white : tint)
							.frame(width: 50, height: 50)
							.background(isOn ? tint : tint.opacity(0.16), in: .circle)
							.symbolEffect(.bounce, value: index)
						
						VStack(alignment: .leading, spacing: 2) {
							Text(look.name)
								.font(.headline)
								.lineLimit(1)
							
							Text(list.status(at: index))
								.font(.subheadline)
								.foregroundStyle(.secondary)
								.lineLimit(1)
							
							if hasCues, let index, let next = list.next(after: index) {
								Text("Next · \(list.title(at: next))")
									.font(.caption)
									.foregroundStyle(.secondary)
									.lineLimit(1)
							}
						}
						
						Spacer(minLength: 0)
					}
					.contentShape(.rect)
				}
				.buttonStyle(PressStyle(flashes: look.tap == .flash) { isHeld in
					console.flash(list, among: lists, isHeld: isHeld)
				})
				.accessibilityHint(look.tap.tapName)
				
				Menu {
					SceneActions(look: look, list: list, lists: lists, recording: $recording, showing: $showing, deleting: $deleting)
				} label: {
					Image(systemName: "ellipsis")
						.font(.body.weight(.semibold))
						.frame(width: 36, height: 36)
				}
				.buttonStyle(.glass)
				.buttonBorderShape(.circle)
				.accessibilityLabel("\(look.name) Actions")
			}
			
			if hasCues {
				HStack(spacing: 4) {
					ForEach(list.cues.indices, id: \.self) { position in
						Capsule()
							.fill(index.map { position <= $0 } == true ? tint : Color(.tertiarySystemFill))
							.frame(height: 6)
					}
				}
				.accessibilityHidden(true)
			}
			
			if !look.buttons.isEmpty {
				TileButtons(look: look, list: list, lists: lists)
			}
		}
		.foregroundStyle(.primary)
		.padding(16)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		.glassEffect(.regular.tint(isOn ? tint.opacity(0.22) : nil).interactive(), in: .rect(cornerRadius: 26, style: .continuous))
		.overlay {
			RoundedRectangle(cornerRadius: 26, style: .continuous)
				.strokeBorder(Color.accentColor, lineWidth: 2)
				.opacity(isShown ? 1 : 0)
		}
		.contentShape(.dragPreview, RoundedRectangle(cornerRadius: 26, style: .continuous))
		.contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 26, style: .continuous))
		.contextMenu {
			if look.tap != .flash {
				SceneActions(look: look, list: list, lists: lists, recording: $recording, showing: $showing, deleting: $deleting)
			}
		}
		.animation(.snappy, value: index)
		.sensoryFeedback(.impact(weight: .medium), trigger: index)
	}
}

private struct TileButtons: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.modelContext) private var context
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	@Query(sort: \Cue.sortIndex) private var cues: [Cue]
	
	let look: Look
	let list: CueList
	let lists: [CueList]
	
	var body: some View {
		let index = list.index(of: console.playback.cue(of: look.identifier))
		let current = index.flatMap { position in cues.first { $0.identifier == list.cues[position].identifier } }
		
		HStack(spacing: 8) {
			ForEach(look.buttons) { action in
				switch action {
				case .flash:
					Button {} label: {
						Label(action.name, systemImage: action.symbol)
							.frame(maxWidth: .infinity, minHeight: 40)
							.glassEffect(.regular.interactive(), in: .capsule)
					}
					.buttonStyle(PressStyle(flashes: true) { isHeld in
						console.flash(list, among: lists, isHeld: isHeld)
					})
				case .update:
					Button {
						if let current {
							Recording(.into(current), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues).update(context: context)
						}
					} label: {
						Label(action.name, systemImage: action.symbol)
							.frame(maxWidth: .infinity)
					}
					.disabled(current == nil || console.active.isEmpty)
				case .toggle:
					Button {
						console.run(action, on: list, among: lists)
					} label: {
						Label(index == nil ? "On" : "Off", systemImage: action.symbol)
							.frame(maxWidth: .infinity)
					}
				case .next, .back:
					Button {
						console.run(action, on: list, among: lists)
					} label: {
						Label(action.name, systemImage: action.symbol)
							.frame(maxWidth: .infinity)
					}
					.disabled(list.cues.count < 2 || (action == .back && index == nil))
				}
			}
		}
		.font(.subheadline.weight(.medium))
		.lineLimit(1)
		.buttonStyle(.glass)
		.frame(minHeight: 40)
	}
}

private struct PressStyle: ButtonStyle {
	let flashes: Bool
	let held: (Bool) -> Void
	
	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.scaleEffect(configuration.isPressed ? 0.97 : 1)
			.animation(.snappy(duration: 0.15), value: configuration.isPressed)
			.onChange(of: configuration.isPressed) {
				if flashes { held(configuration.isPressed) }
			}
	}
}

private struct SceneActions: View {
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
	@Binding var deleting: Look?
	
	var body: some View {
		let index = list.index(of: console.playback.cue(of: look.identifier))
		let current = index.flatMap { position in cues.first { $0.identifier == list.cues[position].identifier } }
		
		if list.cues.count > 1, let index {
			Button("Next Cue", systemImage: "forward.end") {
				console.go(list)
			}
			
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
		
		Button(index == nil ? "Turn On" : "Turn Off", systemImage: index == nil ? "play.circle" : "stop.circle") {
			console.toggle(list, among: lists)
		}
		
		if let current {
			Button("Update Cue", systemImage: "arrow.triangle.2.circlepath") {
				Recording(.into(current), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues).update(context: context)
			}
			.disabled(console.active.isEmpty)
		}
		
		Divider()
		
		Button("Cues and Settings", systemImage: "slider.horizontal.3") {
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
			deleting = look
		}
	}
}
