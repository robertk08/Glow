import SwiftData
import SwiftUI

struct SceneTile: View {
	@Environment(Console.self) private var console
	@Environment(\.modelContext) private var context
	@Environment(\.horizontalSizeClass) private var sizeClass
	@Query(sort: \Cue.sortIndex) private var cues: [Cue]
	
	let look: Look
	let list: CueList
	
	@Binding var isEditing: Bool
	@Binding var customizing: Look?
	@Binding var dragging: String?
	
	@State private var isDeleting = false
	@State private var size = CGSize.zero
	
	var body: some View {
		if !look.isGone {
			content
		}
	}
	
	@ViewBuilder private var content: some View {
		Button {
			if isEditing {
				customizing = look
			} else if look.tap == .open {
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
		.buttonStyle(PressStyle(flashes: look.tap == .flash && !isEditing) { isHeld in
			console.flash(list, isHeld: isHeld)
		})
		.accessibilityHint(isEditing ? "Customizes it." : look.tap.tapName)
		.modifier(SceneMenu(isShown: look.tap != .flash && !isEditing) {
			SceneActions(look: look, list: list, isEditing: $isEditing, isDeleting: $isDeleting, customizing: $customizing)
		} preview: {
			SceneFace(look: look, list: list, showsButtons: true)
				.frame(width: size.width, height: size.height)
				.environment(console)
		})
		.overlay(alignment: .topTrailing) {
			HStack(spacing: 6) {
				if look.size == .wide, !isEditing {
					TileButtons(look: look, list: list)
				}
				
				if list.cues.count > 1, !isEditing {
					Button("Show Cues", systemImage: "list.bullet") {
						console.selection.scene = look.identifier
						console.selection.isSceneOpen = sizeClass != .regular
					}
					.labelStyle(.iconOnly)
					.font(.body.weight(.semibold))
					.foregroundStyle(.secondary)
					.frame(width: 44, height: 44)
					.contentShape(.rect)
					.buttonStyle(.plain)
				}
			}
			.padding(11)
		}
		.overlay(alignment: .bottom) {
			if look.size == .large, !isEditing {
				TileButtons(look: look, list: list)
					.padding(14)
			}
		}
		.overlay(alignment: .topLeading) {
			if isEditing {
				Button("Delete \(look.name)", systemImage: "minus") {
					isDeleting = true
				}
				.labelStyle(.iconOnly)
				.font(.footnote.weight(.bold))
				.foregroundStyle(.primary)
				.frame(width: 28, height: 28)
				.glassEffect(.regular.interactive(), in: .circle)
				.buttonStyle(.plain)
				.offset(x: -8, y: -8)
				.transition(.scale.combined(with: .opacity))
			}
		}
		.confirmationDialog("Delete \(look.name)?", isPresented: $isDeleting, titleVisibility: .visible) {
			Button("Delete Scene", role: .destructive) {
				console.remove(look, with: cues, context: context)
			}
		}
		.onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
		.contentShape(.dragPreview, RoundedRectangle(cornerRadius: 24, style: .continuous))
		.animation(.snappy, value: isEditing)
		.modifier(Arranging(look: look, isOn: isEditing, dragging: $dragging))
		.layoutValue(key: TileSpan.self, value: look.size)
	}
}

private struct Arranging: ViewModifier {
	@Environment(Console.self) private var console
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	
	let look: Look
	let isOn: Bool
	
	@Binding var dragging: String?
	
	func body(content: Content) -> some View {
		if isOn {
			content
				.opacity(dragging == look.identifier ? 0.4 : 1)
				.onDrag {
					dragging = look.identifier
					return NSItemProvider(object: look.identifier as NSString)
				}
				.dropDestination(for: String.self) { _, _ in
					dragging = nil
					return true
				} isTargeted: { isTargeted in
					guard isTargeted, let from = looks.firstIndex(where: { $0.identifier == dragging }), let to = looks.firstIndex(where: { $0.identifier == look.identifier }), from != to else { return }
					console.move(IndexSet(integer: from), to: to > from ? to + 1 : to, among: looks, sortIndex: \.sortIndex)
				}
		} else {
			content
		}
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

private struct SceneActions: View {
	@Environment(Console.self) private var console
	@Environment(\.modelContext) private var context
	@Environment(\.horizontalSizeClass) private var sizeClass
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	@Query(sort: \Cue.sortIndex) private var cues: [Cue]
	
	let look: Look
	let list: CueList
	
	@Binding var isEditing: Bool
	@Binding var isDeleting: Bool
	@Binding var customizing: Look?
	
	var body: some View {
		let index = list.index(of: console.playback.cue(of: look.identifier))
		
		Section {
			if list.cues.count > 1, index != nil {
				Button("Next Cue", systemImage: SceneAction.next.symbol) {
					console.go(list)
				}
				.disabled(console.upcoming(list) == nil)
				
				Button("Previous Cue", systemImage: SceneAction.back.symbol) {
					console.back(list)
				}
			}
			
			if !list.cues.isEmpty {
				Button(index != nil ? "Turn Off" : list.cues.count > 1 ? "Start" : "Turn On", systemImage: SceneAction.toggle.symbol(isOn: index != nil)) {
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
		}
		
		Section {
			Button("Customize", systemImage: "slider.horizontal.3") {
				customizing = look
			}
			
			Button("Duplicate", systemImage: "plus.square.on.square") {
				look.duplicate(with: cues, among: looks, context: context)
			}
			
			Button("Edit Scenes", systemImage: "square.grid.2x2") {
				isEditing = true
			}
			
			Button("Delete Scene", systemImage: "trash", role: .destructive) {
				isDeleting = true
			}
		}
	}
}
