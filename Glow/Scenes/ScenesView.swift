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
	@State private var deleting: Look?
	@State private var isOrdering = false
	@ScaledMetric(relativeTo: .headline) private var tileWidth = 168
	
	@ViewBuilder private var tiles: some View {
		let lists = looks.map { CueList($0, cues: cues, fixtures: fixtures, library: library) }
		let items = ForEach(Array(zip(looks, lists)), id: \.0.identifier) { look, list in
			SceneTile(look: look, list: list, lists: lists, recording: $recording, deleting: $deleting)
		}
		let grid = TileLayout(minimum: typeSize.isAccessibilitySize ? 300 : tileWidth, spacing: 12) {
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
					Text(fixtures.isEmpty ? "Patch a light first, then come back to store how it looks." : "A new scene opens on the lights. Set them, store a cue, change them and store the next.")
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
			
			if console.playback.playing.contains(where: { entry in looks.contains { $0.identifier == entry.scene } }) {
				ToolbarItem(placement: .topBarTrailing) {
					Button("All Off", systemImage: "power") {
						console.stopAll(among: looks.map { CueList($0, cues: cues, fixtures: fixtures, library: library) })
					}
				}
				
				ToolbarSpacer(.fixed, placement: .topBarTrailing)
			}
			
			ToolbarItem(placement: .topBarTrailing) {
				Button("Reorder", systemImage: "arrow.up.arrow.down") {
					isOrdering = true
				}
				.disabled(looks.count < 2)
			}
			
			ToolbarSpacer(.fixed, placement: .topBarTrailing)
			
			ToolbarItem(placement: .topBarTrailing) {
				Button("New Scene", systemImage: "plus") {
					console.selection.building = Look.fresh(among: looks, context: context).identifier
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

struct SceneTile: View {
	@Environment(Console.self) private var console
	@Environment(\.horizontalSizeClass) private var sizeClass
	
	let look: Look
	let list: CueList
	let lists: [CueList]
	
	@Binding var recording: Recording?
	@Binding var deleting: Look?
	
	var body: some View {
		let index = list.index(of: console.playback.cue(of: look.identifier))
		let isOn = index != nil
		let tint = look.tint.color ?? .accentColor
		
		VStack(alignment: .leading, spacing: 8) {
			HStack(alignment: .bottom, spacing: 12) {
				Button {
					if list.cues.isEmpty {
						console.selection.building = look.identifier
					} else {
						console.run(look.tap, on: list, among: lists)
					}
				} label: {
					VStack(alignment: .leading, spacing: 8) {
						Image(systemName: look.symbol)
							.font(.title3)
							.foregroundStyle(isOn ? Color.white : tint)
							.frame(width: 38, height: 38)
							.background(isOn ? tint : tint.opacity(0.16), in: .circle)
							.symbolEffect(.bounce, value: index)
						
						VStack(alignment: .leading, spacing: 1) {
							Text(look.name)
								.font(.headline)
							
							Text(list.status(at: index))
								.font(.caption2)
								.foregroundStyle(.secondary)
								.contentTransition(.numericText())
						}
						.lineLimit(1)
					}
					.frame(maxWidth: .infinity, alignment: .leading)
					.contentShape(.rect)
				}
				.buttonStyle(PressStyle(flashes: look.tap == .flash) { isHeld in
					console.flash(list, among: lists, isHeld: isHeld)
				})
				.accessibilityHint(look.tap.tapName)
				
				if !look.buttons.isEmpty {
					TileButtons(look: look, list: list, lists: lists)
						.frame(maxWidth: 200)
				}
			}
			
			HStack(spacing: list.cues.count > 16 ? 1 : 3) {
				ForEach(list.cues.indices, id: \.self) { position in
					if position == index {
						FadeBar(fade: console.fades[look.identifier], tint: tint)
					} else {
						Capsule()
							.fill(index.map { position < $0 } == true ? tint : Color(.tertiarySystemFill))
							.frame(height: 6)
					}
				}
				
				if list.cues.isEmpty {
					Capsule()
						.fill(Color(.tertiarySystemFill))
						.frame(height: 6)
				}
			}
			.padding(.vertical, 6)
			.accessibilityHidden(true)
		}
		.padding(14)
		.frame(maxWidth: .infinity, alignment: .topLeading)
		.overlay(alignment: .topTrailing) {
			Button {
				console.selection.scene = look.identifier
				console.selection.isSceneOpen = sizeClass != .regular
			} label: {
				Image(systemName: "ellipsis")
					.font(.body.weight(.semibold))
					.foregroundStyle(.secondary)
					.frame(width: 44, height: 44)
					.contentShape(.rect)
			}
			.buttonStyle(.plain)
			.padding(4)
			.accessibilityLabel("Open \(look.name)")
		}
		.glassEffect(.regular.tint(isOn ? tint.opacity(0.22) : nil), in: .rect(cornerRadius: 24, style: .continuous))
		.contentShape(.dragPreview, RoundedRectangle(cornerRadius: 24, style: .continuous))
		.contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 24, style: .continuous))
		.contextMenu(look.tap == .flash || look.buttons.contains(.flash) ? nil : ContextMenu {
			SceneActions(look: look, list: list, lists: lists, recording: $recording, deleting: $deleting)
		})
		.animation(.snappy, value: index)
		.sensoryFeedback(.impact(weight: .medium), trigger: index)
		.layoutValue(key: TileSpan.self, value: look.buttons.isEmpty ? 1 : 2)
	}
}

struct TileButtons: View {
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
		
		HStack(spacing: 6) {
			ForEach(look.buttons.prefix(Look.buttonLimit)) { action in
				let isEnabled = switch action {
				case .update: current != nil && console.hasProgrammer
				case .next: !list.cues.isEmpty
				case .back: list.cues.count > 1 && index != nil
				case .toggle, .flash: !list.cues.isEmpty
				}
				
				Button {
					if action == .update, let current {
						Recording(.into(current), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues).update(context: context)
					} else if action != .flash {
						console.run(action, on: list, among: lists)
					}
				} label: {
					Label(action == .toggle ? (index == nil ? "Turn On" : "Turn Off") : action.name, systemImage: action.symbol)
						.labelStyle(.iconOnly)
						.font(.body.weight(.semibold))
						.foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
						.frame(maxWidth: .infinity, minHeight: 40)
						.glassEffect(.regular.interactive(isEnabled), in: .capsule)
						.contentShape(.capsule)
				}
				.buttonStyle(PressStyle(flashes: action == .flash) { isHeld in
					console.flash(list, among: lists, isHeld: isHeld)
				})
				.disabled(!isEnabled)
			}
		}
	}
}

nonisolated struct TileSpan: LayoutValueKey {
	static let defaultValue = 1
}

struct TileLayout: Layout {
	let minimum: CGFloat
	let spacing: CGFloat
	
	func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
		let width = proposal.width ?? minimum * 2 + spacing
		let placed = cells(of: subviews, width: width)
		return CGSize(width: width, height: placed.map { $0.frame.maxY }.max() ?? 0)
	}
	
	func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
		for cell in cells(of: subviews, width: bounds.width) {
			subviews[cell.index].place(at: CGPoint(x: bounds.minX + cell.frame.minX, y: bounds.minY + cell.frame.minY), proposal: ProposedViewSize(cell.frame.size))
		}
	}
	
	private func cells(of subviews: Subviews, width: CGFloat) -> [(index: Int, frame: CGRect)] {
		let columns = max(1, Int((width + spacing) / (minimum + spacing)))
		let column = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
		let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: column, height: nil)).height }.max() ?? 0
		var used: [Int] = []
		var cells: [(index: Int, frame: CGRect)] = []
		
		for (index, subview) in subviews.enumerated() {
			let span = min(subview[TileSpan.self], columns)
			let row = used.firstIndex { columns - $0 >= span } ?? used.count
			if row == used.count { used.append(0) }
			let x = CGFloat(used[row]) * (column + spacing)
			let frame = CGRect(x: x, y: CGFloat(row) * (height + spacing), width: column * CGFloat(span) + spacing * CGFloat(span - 1), height: height)
			cells.append((index, frame))
			used[row] += span
		}
		
		return cells
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
	@Binding var deleting: Look?
	
	var body: some View {
		let index = list.index(of: console.playback.cue(of: look.identifier))
		let current = index.flatMap { position in cues.first { $0.identifier == list.cues[position].identifier } }
		
		Section {
			if list.cues.count > 1 {
				Button("Next Cue", systemImage: "forward.end.fill") {
					console.go(list)
				}
				
				if index != nil {
					Button("Previous Cue", systemImage: "backward.end.fill") {
						console.back(list)
					}
				}
			}
			
			if !list.cues.isEmpty {
				Button(index == nil ? "Turn On" : "Turn Off", systemImage: "power") {
					console.toggle(list, among: lists)
				}
			}
			
			if let current {
				Button("Update Cue", systemImage: "arrow.triangle.2.circlepath") {
					Recording(.into(current), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues).update(context: context)
				}
				.disabled(!console.hasProgrammer)
			}
		}
		
		Section {
			Button("Show Cues", systemImage: "list.bullet") {
				console.selection.scene = look.identifier
				console.selection.isSceneOpen = sizeClass != .regular
			}
			
			Button("Add Cues", systemImage: "plus") {
				console.selection.building = look.identifier
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
