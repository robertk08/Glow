import SwiftData
import SwiftUI

struct ScenesView: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	@Environment(ShowLibrary.self) private var shows
	@Environment(\.modelContext) private var context
	@Environment(\.dynamicTypeSize) private var typeSize
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	@Query(sort: \Cue.number) private var cues: [Cue]
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	@State private var recording: Recording?
	@State private var renaming: Look?
	@State private var renamed = ""
	@State private var deleting: Look?
	@State private var isOrdering = false
	@ScaledMetric(relativeTo: .headline) private var tileWidth = 168
	
	private var columns: [GridItem] {
		[GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 300 : tileWidth), spacing: 12)]
	}
	
	@ViewBuilder private var tiles: some View {
		let items = ForEach(looks) { look in
			SceneTile(look: look, list: CueList(look, cues: cues, fixtures: fixtures, library: library), recording: $recording, renaming: $renaming, renamed: $renamed, deleting: $deleting)
		}
		let grid = LazyVGrid(columns: columns, spacing: 12) {
			if #available(iOS 27.0, *) {
				items.reorderable()
			} else {
				items
			}
		}
		.padding(.horizontal)
		.padding(.bottom, 24)
		
		if #available(iOS 27.0, *) {
			grid.reorderContainer(for: Look.self) { difference in
				console.move(difference, among: looks, sortIndex: \.sortIndex)
			}
		} else {
			grid
		}
	}
	
	var body: some View {
		let playing = cues.first { $0.identifier == console.activeCue }
		let stage = looks.first { $0.identifier == playing?.lookID }
		
		Group {
			if looks.isEmpty {
				ContentUnavailableView {
					Label("No Scenes Yet", systemImage: "theatermasks")
				} description: {
					Text(fixtures.isEmpty ? "Patch a light first, set it how you want it, then store the look here." : "Set the rig how you want it, then store it. One tap brings a scene back. Add cues to it and it becomes a cue list you run with Go.")
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
		.safeAreaBar(edge: .bottom) {
			if let stage, stage.cues(among: cues).count > 1 {
				PlaybackDeck(look: stage)
			}
		}
		.navigationTitle("Scenes")
		.navigationSubtitle(shows.active.name)
		.navigationDestination(for: Look.self) { look in
			CueListView(look: look)
		}
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
		.sheet(isPresented: $isOrdering) {
			NavigationStack {
				List {
					ForEach(looks) { look in
						Label(look.name, systemImage: look.cues(among: cues).count > 1 ? "list.number" : "theatermasks")
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
		.alert("Rename Scene", isPresented: Binding { renaming != nil } set: { _ in renaming = nil }, presenting: renaming) { look in
			TextField("Name", text: $renamed)
				.autocorrectionDisabled()
			
			Button("Cancel", role: .cancel) {}
			
			Button("Rename") {
				look.name = renamed.trimmingCharacters(in: .whitespaces)
			}
			.disabled(renamed.trimmingCharacters(in: .whitespaces).isEmpty)
		}
		.confirmationDialog("Delete \(deleting?.name ?? "Scene")?", isPresented: Binding { deleting != nil } set: { _ in deleting = nil }, titleVisibility: .visible, presenting: deleting) { look in
			Button("Delete Scene", role: .destructive) {
				look.remove(with: cues, context: context)
			}
		} message: { look in
			Text(look.cues(among: cues).count > 1 ? "Its \(look.cues(among: cues).count) cues go with it. The lights stay as they are." : "The lights stay as they are.")
		}
		.sensoryFeedback(.success, trigger: console.activeCue)
	}
}

private struct SceneTile: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.modelContext) private var context
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	@Query(sort: \Cue.number) private var cues: [Cue]
	
	let look: Look
	let list: CueList
	
	@Binding var recording: Recording?
	@Binding var renaming: Look?
	@Binding var renamed: String
	@Binding var deleting: Look?
	
	var body: some View {
		let index = list.index(of: console.activeCue)
		let current = cues.first { $0.identifier == console.activeCue && $0.lookID == look.identifier }
		
		VStack(alignment: .leading, spacing: 10) {
			HStack(alignment: .top, spacing: 8) {
				SpotStrip(spots: list.spots(at: index ?? 0), size: 18, limit: 7)
					.frame(height: 32)
				
				Spacer(minLength: 0)
				
				NavigationLink(value: look) {
					Image(systemName: list.cues.count > 1 ? "list.number" : "slider.horizontal.3")
						.font(.subheadline.weight(.semibold))
						.frame(width: 32, height: 32)
				}
				.buttonStyle(.glass)
				.buttonBorderShape(.circle)
				.accessibilityLabel("Cues")
			}
			
			VStack(alignment: .leading, spacing: 1) {
				Text(look.name)
					.font(.headline)
					.lineLimit(1)
				
				Text(list.summary(at: index))
					.font(.caption2)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
			
			if let index {
				CueProgress(cue: list.cues[index])
			}
		}
		.foregroundStyle(.primary)
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(14)
		.glassEffect(.regular.tint(index != nil ? Color.accentColor.opacity(0.35) : nil).interactive(), in: .rect(cornerRadius: 24, style: .continuous))
		.contentShape(.rect(cornerRadius: 24, style: .continuous))
		.onTapGesture {
			console.go(list)
		}
		.contentShape(.dragPreview, RoundedRectangle(cornerRadius: 24, style: .continuous))
		.accessibilityElement(children: .combine)
		.accessibilityAddTraits(.isButton)
		.accessibilityAddTraits(index != nil ? .isSelected : [])
		.accessibilityHint(list.cues.count > 1 ? "Runs the next cue." : "Brings the scene back.")
		.contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 24, style: .continuous))
		.contextMenu {
			Button("Add Cue", systemImage: "plus.rectangle.on.rectangle") {
				recording = Recording(.cue(look), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues)
			}
			
			if let current {
				Button("Update Cue \(current.numberText)", systemImage: "square.and.arrow.down") {
					Recording(.into(current), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues).store(context: context)
				}
				.disabled(console.active.isEmpty)
			}
			
			if list.cues.count > 1 {
				Toggle("Loop", systemImage: "repeat", isOn: Bindable(look).loops)
			}
			
			Divider()
			
			Button("Rename", systemImage: "pencil") {
				renamed = look.name
				renaming = look
			}
			
			Button("Duplicate", systemImage: "plus.square.on.square") {
				look.duplicate(with: cues, among: looks, context: context)
			}
			
			Button("Delete Scene", systemImage: "trash", role: .destructive) {
				deleting = look
			}
		}
	}
}
