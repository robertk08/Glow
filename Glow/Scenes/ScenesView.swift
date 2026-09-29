import SwiftData
import SwiftUI

struct ScenesView: View {
	@Environment(Console.self) private var console
	@Environment(ShowLibrary.self) private var shows
	@Environment(\.dynamicTypeSize) private var typeSize
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	@Query(sort: \Cue.sortIndex) private var cues: [Cue]
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	@State private var deleting: Look?
	@State private var customizing: Look?
	@State private var isOrdering = false
	@ScaledMetric(relativeTo: .headline) private var tileWidth = 168
	
	@ViewBuilder private var tiles: some View {
		let lists = CueList.all(looks, cues: cues, fixtures: fixtures)
		let items = ForEach(Array(zip(looks, lists)), id: \.0.identifier) { look, list in
			SceneTile(look: look, list: list, deleting: $deleting, customizing: $customizing)
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
		let isPlaying = console.playback.playing.contains { entry in looks.contains { $0.identifier == entry.scene } }
		
		Group {
			if looks.isEmpty {
				ContentUnavailableView {
					Label("No Scenes Yet", systemImage: "theatermasks")
				} description: {
					if fixtures.isEmpty {
						Text("Patch a light first.")
					} else {
						Text("Set the lights on the Lights tab, then store them here to bring them back with one tap.")
					}
				} actions: {
					Button("New Scene", systemImage: "plus") {
						console.selection.isNaming = true
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
				Button("All Off", systemImage: "power") {
					console.stopAll()
				}
				.disabled(!isPlaying)
			}
			
			ToolbarSpacer(.fixed, placement: .topBarTrailing)
			
			ToolbarItem(placement: .topBarTrailing) {
				Button("Reorder", systemImage: "arrow.up.arrow.down") {
					isOrdering = true
				}
				.disabled(looks.count < 2)
			}
			
			ToolbarSpacer(.fixed, placement: .topBarTrailing)
			
			ToolbarItem(placement: .topBarTrailing) {
				Button("New Scene", systemImage: "plus") {
					console.selection.isNaming = true
				}
				.disabled(fixtures.isEmpty)
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
	}
}

struct SceneTile: View {
	@Environment(Console.self) private var console
	@Environment(\.modelContext) private var context
	@Environment(\.horizontalSizeClass) private var sizeClass
	@Query(sort: \Cue.sortIndex) private var cues: [Cue]
	
	let look: Look
	let list: CueList
	
	@Binding var deleting: Look?
	@Binding var customizing: Look?
	
	@State private var size = CGSize.zero
	
	var body: some View {
		if !look.isGone {
			content
		}
	}
	
	@ViewBuilder private var content: some View {
		let buttons = TileButtons(look: look, list: list)
		
		Button {
			if look.tap == .open {
				console.selection.scene = look.identifier
				console.selection.isSceneOpen = sizeClass != .regular
			} else if list.cues.isEmpty {
				console.selection.building = look.identifier
			} else {
				console.run(look.tap, on: list)
			}
		} label: {
			SceneFace(look: look, list: list)
		}
		.buttonStyle(PressStyle(flashes: look.tap == .flash) { isHeld in
			console.flash(list, isHeld: isHeld)
		})
		.accessibilityHint(look.tap.tapName)
		.modifier(SceneMenu(isShown: look.tap != .flash) {
			SceneActions(look: look, list: list, deleting: $deleting, customizing: $customizing)
		} preview: {
			SceneFace(look: look, list: list)
				.overlay(alignment: .topTrailing) {
					if look.size == .wide {
						HStack(spacing: 6) {
							buttons
							
							Color.clear
								.frame(width: 44, height: 44)
						}
						.padding(11)
					}
				}
				.overlay(alignment: .bottom) {
					if look.size == .large {
						buttons
							.padding(14)
					}
				}
				.frame(width: size.width, height: size.height)
				.environment(console)
		})
		.overlay(alignment: .topTrailing) {
			HStack(spacing: 6) {
				if look.size == .wide {
					buttons
				}
				
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
				.accessibilityLabel("Open \(look.name)")
				.modifier(SceneMenu(isShown: look.tap == .flash) {
					SceneActions(look: look, list: list, deleting: $deleting, customizing: $customizing)
				} preview: {
					SceneFace(look: look, list: list)
						.frame(width: size.width, height: size.height)
						.environment(console)
				})
			}
			.padding(11)
		}
		.overlay(alignment: .bottom) {
			if look.size == .large {
				buttons
					.padding(14)
			}
		}
		.confirmationDialog("Delete \(look.name)?", isPresented: Binding { deleting?.identifier == look.identifier } set: { if !$0 { deleting = nil } }, titleVisibility: .visible) {
			Button("Delete Scene", role: .destructive) {
				console.remove(look, with: cues, context: context)
			}
		}
		.onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
		.contentShape(.dragPreview, RoundedRectangle(cornerRadius: 24, style: .continuous))
		.animation(.snappy, value: console.playback.cue(of: look.identifier))
		.layoutValue(key: TileSpan.self, value: look.size)
	}
}

private struct SceneFace: View {
	@Environment(Console.self) private var console
	@ScaledMetric(relativeTo: .headline) private var controls = 44
	
	let look: Look
	let list: CueList
	
	var body: some View {
		if !look.isGone {
			content
		}
	}
	
	@ViewBuilder private var content: some View {
		let index = list.index(of: console.playback.cue(of: look.identifier))
		let isOn = index != nil
		let tint = look.tint.color ?? .accentColor
		let fade = console.playback.fades[look.identifier]
		let upcoming = console.upcoming(list)
		
		VStack(alignment: .leading, spacing: 8) {
			Image(systemName: look.symbol)
				.font(.title3)
				.foregroundStyle(isOn ? Color.white : tint)
				.frame(width: 38, height: 38)
				.background(isOn ? tint : tint.opacity(0.16), in: .circle)
				.symbolEffect(.bounce, value: index)
			
			VStack(alignment: .leading, spacing: 2) {
				Text(look.name)
					.font(.headline)
					.lineLimit(1)
				
				CueStatus(text: list.status(at: index), fade: fade, follow: index.flatMap { list.cues[$0].follow })
					.font(look.size == .large ? .title3.weight(.semibold) : .footnote)
					.foregroundStyle(look.size == .large ? .primary : .secondary)
					.lineLimit(look.size == .large ? 2 : 1)
					.contentTransition(.numericText())
				
				if look.size == .large, list.cues.count > 1, let upcoming {
					Text("Next: \(list.heading(at: upcoming))")
						.font(.footnote)
						.foregroundStyle(.secondary)
						.lineLimit(1)
						.contentTransition(.numericText())
				}
			}
			
			if look.size == .large {
				Spacer(minLength: 0)
			}
			
			CueProgress(list: list, index: index, fade: fade, tint: tint)
				.padding(.vertical, 6)
			
			if look.size == .large {
				Color.clear
					.frame(height: controls)
			}
		}
		.foregroundStyle(.primary)
		.padding(14)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		.glassEffect(.regular.tint(isOn ? tint.opacity(0.22) : nil), in: .rect(cornerRadius: 24, style: .continuous))
		.contentShape(.rect(cornerRadius: 24, style: .continuous))
	}
}

private struct CueProgress: View {
	let list: CueList
	let index: Int?
	let fade: Fade?
	let tint: Color
	
	var body: some View {
		Group {
			if list.isLong {
				ProgressView(value: Double(index.map { $0 + 1 } ?? 0), total: Double(list.cues.count))
			} else {
				HStack(spacing: 3) {
					ForEach(list.cues.indices, id: \.self) { position in
						if position == index {
							FadeBar(fade: fade, tint: tint)
						} else {
							ProgressView(value: index.map { position < $0 } == true ? 1 : 0)
						}
					}
					
					if list.cues.isEmpty {
						ProgressView(value: 0)
					}
				}
			}
		}
		.progressViewStyle(.linear)
		.tint(tint)
		.accessibilityHidden(true)
	}
}

private struct SceneMenu<Items: View, Preview: View>: ViewModifier {
	let isShown: Bool
	@ViewBuilder let items: Items
	@ViewBuilder let preview: Preview
	
	init(isShown: Bool, @ViewBuilder items: () -> Items, @ViewBuilder preview: () -> Preview) {
		self.isShown = isShown
		self.items = items()
		self.preview = preview()
	}
	
	func body(content: Content) -> some View {
		if isShown {
			content
				.contextMenu {
					items
				} preview: {
					preview
				}
		} else {
			content
		}
	}
}

struct TileButtons: View {
	@Environment(Console.self) private var console
	@ScaledMetric(relativeTo: .headline) private var height = 44
	
	let look: Look
	let list: CueList
	
	var body: some View {
		if !look.isGone {
			content
		}
	}
	
	@ViewBuilder private var content: some View {
		let index = list.index(of: console.playback.cue(of: look.identifier))
		let isLarge = look.size == .large
		let tint = look.tint.color ?? .accentColor
		
		HStack(spacing: isLarge ? 10 : 6) {
			ForEach(look.buttons) { action in
				let isEnabled = action == .back ? list.cues.count > 1 && index != nil : !list.cues.isEmpty
				let isProminent = isLarge && action == .next && isEnabled
				
				Button {
					if action != .flash {
						console.run(action, on: list)
					}
				} label: {
					Label(action == .toggle ? (index == nil ? "Turn On" : "Turn Off") : action.name, systemImage: action.symbol)
						.labelStyle(.iconOnly)
						.font(.body.weight(.semibold))
						.foregroundStyle(isProminent ? AnyShapeStyle(.white) : isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
						.frame(minWidth: 48, maxWidth: isLarge ? .infinity : 48, minHeight: isLarge ? height : 40)
						.glassEffect(.regular.tint(isProminent ? tint : nil).interactive(isEnabled), in: .capsule)
						.contentShape(.capsule)
				}
				.buttonStyle(PressStyle(flashes: action == .flash) { isHeld in
					console.flash(list, isHeld: isHeld)
				})
				.disabled(!isEnabled)
			}
		}
	}
}

nonisolated struct TileSpan: LayoutValueKey {
	static let defaultValue = TileSize.small
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
		let spans = subviews.map { (across: min($0[TileSpan.self].columns, columns), down: $0[TileSpan.self].rows) }
		let height = zip(subviews, spans).map { subview, span in
			let width = column * CGFloat(span.across) + spacing * CGFloat(span.across - 1)
			return (subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height - spacing * CGFloat(span.down - 1)) / CGFloat(span.down)
		}.max() ?? 0
		var taken = Set<Int>()
		var cells: [(index: Int, frame: CGRect)] = []
		
		for (index, span) in spans.enumerated() {
			var slot = 0
			
			while slot % columns + span.across > columns || (0..<span.down).contains(where: { line in (0..<span.across).contains { taken.contains(slot + line * columns + $0) } }) {
				slot += 1
			}
			
			for line in 0..<span.down {
				for place in 0..<span.across {
					taken.insert(slot + line * columns + place)
				}
			}
			
			let frame = CGRect(x: CGFloat(slot % columns) * (column + spacing), y: CGFloat(slot / columns) * (height + spacing), width: column * CGFloat(span.across) + spacing * CGFloat(span.across - 1), height: height * CGFloat(span.down) + spacing * CGFloat(span.down - 1))
			cells.append((index, frame))
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
	@Environment(\.modelContext) private var context
	@Environment(\.horizontalSizeClass) private var sizeClass
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	@Query(sort: \Cue.sortIndex) private var cues: [Cue]
	
	let look: Look
	let list: CueList
	
	@Binding var deleting: Look?
	@Binding var customizing: Look?
	
	var body: some View {
		let index = list.index(of: console.playback.cue(of: look.identifier))
		
		Section {
			if list.cues.count > 1, index != nil {
				Button("Next Cue", systemImage: "forward.end.fill") {
					console.go(list)
				}
				
				Button("Previous Cue", systemImage: "backward.end.fill") {
					console.back(list)
				}
			}
			
			if !list.cues.isEmpty {
				Button(index != nil ? "Turn Off" : list.cues.count > 1 ? "Start" : "Turn On", systemImage: index != nil ? "stop.fill" : "play.fill") {
					console.toggle(list)
				}
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
			
			Button("Customize", systemImage: "slider.horizontal.3") {
				customizing = look
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
