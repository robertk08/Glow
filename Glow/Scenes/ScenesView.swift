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
	@ScaledMetric(relativeTo: .headline) private var tileWidth = 168
	
	
	@ViewBuilder private var tiles: some View {
		let lists = looks.map { CueList($0, cues: cues, fixtures: fixtures, library: library) }
		let items = ForEach(Array(zip(looks, lists)), id: \.0.identifier) { look, list in
			SceneTile(look: look, list: list, lists: lists, recording: $recording, showing: $showing, deleting: $deleting)
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
			
			if !console.playback.playing.isEmpty {
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
	
	@State private var isBroad = false
	
	var body: some View {
		let index = list.index(of: console.playback.cue(of: look.identifier))
		let isOn = index != nil
		let hasCues = list.cues.count > 1
		let tint = look.tint.color ?? .accentColor
		let isShown = sizeClass == .regular && console.shownScene(among: lists.map(\.scene)) == look.identifier
		let isWide = !look.buttons.isEmpty
		let header = isWide || isBroad ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
		
		return VStack(alignment: .leading, spacing: 10) {
			Button {
				console.selection.scene = look.identifier
				
				if list.cues.isEmpty {
					console.selection.building = look.identifier
				} else {
					console.run(look.tap, on: list, among: lists)
				}
			} label: {
				VStack(alignment: .leading, spacing: 8) {
					header {
						Image(systemName: look.symbol)
							.font(.title3)
							.foregroundStyle(isOn ? Color.white : tint)
							.frame(width: 38, height: 38)
							.background(isOn ? tint : tint.opacity(0.16), in: .circle)
							.symbolEffect(.bounce, value: index)
						
						VStack(alignment: .leading, spacing: 1) {
							Text(look.name)
								.font(.headline)
								.lineLimit(1)
							
							Text(list.status(at: index))
								.font(.caption2)
								.foregroundStyle(.secondary)
								.lineLimit(1)
							
							if hasCues, let next = list.next(after: index) {
								Text("Next · \(list.title(at: next))")
									.font(.caption2)
									.foregroundStyle(.secondary)
									.lineLimit(1)
							}
						}
					}
					.padding(.trailing, isWide || isBroad ? 34 : 0)
					.frame(maxHeight: .infinity, alignment: .top)
					
					if !list.cues.isEmpty {
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
						}
						.padding(.vertical, 6)
						.accessibilityHidden(true)
					}
				}
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
				.contentShape(.rect)
			}
			.buttonStyle(PressStyle(flashes: look.tap == .flash) { isHeld in
				console.flash(list, among: lists, isHeld: isHeld)
			})
			.accessibilityHint(look.tap.tapName)
			.overlay(alignment: .topTrailing) {
				Menu {
					SceneActions(look: look, list: list, lists: lists, recording: $recording, showing: $showing, deleting: $deleting)
				} label: {
					Image(systemName: "ellipsis")
						.font(.body.weight(.semibold))
						.foregroundStyle(.secondary)
						.frame(width: 38, height: 38)
						.contentShape(.rect)
				}
				.accessibilityLabel("\(look.name) Actions")
			}
			
			if !look.buttons.isEmpty {
				TileButtons(look: look, list: list, lists: lists)
			}
		}
		.tint(.primary)
		.padding(14)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		.glassEffect(.regular.tint(isOn ? tint.opacity(0.22) : nil).interactive(), in: .rect(cornerRadius: 24, style: .continuous))
		.overlay {
			RoundedRectangle(cornerRadius: 24, style: .continuous)
				.strokeBorder(Color.accentColor, lineWidth: 2)
				.opacity(isShown ? 1 : 0)
		}
		.contentShape(.dragPreview, RoundedRectangle(cornerRadius: 24, style: .continuous))
		.contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 24, style: .continuous))
		.contextMenu {
			if look.tap != .flash {
				SceneActions(look: look, list: list, lists: lists, recording: $recording, showing: $showing, deleting: $deleting)
			}
		}
		.animation(.snappy, value: index)
		.sensoryFeedback(.impact(weight: .medium), trigger: index)
		.onGeometryChange(for: Bool.self) { $0.size.width > 300 } action: { isBroad = $0 }
		.layoutValue(key: TileSpan.self, value: isWide ? 2 : 1)
	}
}

private nonisolated struct TileSpan: LayoutValueKey {
	static let defaultValue = 1
}

private struct TileLayout: Layout {
	struct Row {
		var y: CGFloat
		var height: CGFloat = 0
		var cells: [(index: Int, x: CGFloat, width: CGFloat)] = []
	}
	
	let minimum: CGFloat
	let spacing: CGFloat
	
	func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
		let width = proposal.width ?? minimum * 2 + spacing
		return CGSize(width: width, height: rows(of: subviews, width: width).last.map { $0.y + $0.height } ?? 0)
	}
	
	func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
		for row in rows(of: subviews, width: bounds.width) {
			for cell in row.cells {
				subviews[cell.index].place(at: CGPoint(x: bounds.minX + cell.x, y: bounds.minY + row.y), proposal: ProposedViewSize(width: cell.width, height: row.height))
			}
		}
	}
	
	private func rows(of subviews: Subviews, width: CGFloat) -> [Row] {
		let columns = max(1, Int((width + spacing) / (minimum + spacing)))
		let column = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
		var rows: [Row] = []
		var row = Row(y: 0)
		var used = 0
		
		for (index, subview) in subviews.enumerated() {
			let span = min(subview[TileSpan.self], columns)
			
			if used + span > columns, let last = row.cells.indices.last {
				row.cells[last].width = width - row.cells[last].x
				rows.append(row)
				row = Row(y: row.y + row.height + spacing)
				used = 0
			}
			
			let cellWidth = column * CGFloat(span) + spacing * CGFloat(span - 1)
			row.cells.append((index, CGFloat(used) * (column + spacing), cellWidth))
			row.height = max(row.height, subview.sizeThatFits(ProposedViewSize(width: cellWidth, height: nil)).height)
			used += span
		}
		
		if !row.cells.isEmpty {
			rows.append(row)
		}
		
		return rows
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
					.disabled(list.cues.count < 2 || action == .back && index == nil)
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
		
		Button("Build Cues", systemImage: "plus.rectangle.on.rectangle") {
			console.selection.building = look.identifier
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
