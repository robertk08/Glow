import SwiftData
import SwiftUI

struct SceneTile: View {
	@Environment(Console.self) private var console
	@Environment(\.modelContext) private var context
	@Environment(\.horizontalSizeClass) private var sizeClass
	@Query(sort: \Cue.sortIndex) private var cues: [Cue]
	
	let look: Look
	let list: CueList
	let arrangement: Arrangement
	
	@Binding var isArranging: Bool
	@Binding var customizing: Look?
	
	@State private var isDeleting = false
	
	var body: some View {
		if !look.isGone {
			content
		}
	}
	
	@ViewBuilder private var content: some View {
		Button {
			if look.tap == .open {
				console.selection.scene = look.identifier
				console.selection.isSceneOpen = sizeClass != .regular
			} else if list.cues.isEmpty {
				console.selection.build(look.identifier)
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
		.overlay {
			TileControls(look: look, list: list)
		}
		.contentShape(.contextMenuPreview, .rect(cornerRadius: 24, style: .continuous))
		.modifier(SceneMenu(isShown: look.tap != .flash) {
			if !console.flashing.contains(list.scene) {
				SceneActions(look: look, list: list, isArranging: $isArranging, isDeleting: $isDeleting, customizing: $customizing)
			}
		})
		.confirmationDialog("Delete \(look.name)?", isPresented: $isDeleting, titleVisibility: .visible) {
			Button("Delete Scene", role: .destructive) {
				console.remove(look, with: cues, context: context)
			}
		}
		.onGeometryChange(for: CGRect.self) { $0.frame(in: .named("tiles")) } action: { frame in
			arrangement.frames[look.identifier] = frame
		}
		.layoutValue(key: TileSpan.self, value: look.size)
		.layoutValue(key: TileSlot.self, value: look.slot)
	}
}

private struct SceneMenu<Items: View>: ViewModifier {
	let isShown: Bool
	@ViewBuilder let items: Items
	
	init(isShown: Bool, @ViewBuilder items: () -> Items) {
		self.isShown = isShown
		self.items = items()
	}
	
	func body(content: Content) -> some View {
		if isShown {
			content
				.contextMenu {
					items
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
	
	@Binding var isArranging: Bool
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
				.disabled(index.flatMap(list.previous(before:)) == nil)
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
				console.selection.build(look.identifier)
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
				isArranging = true
			}
			
			Button("Delete Scene", systemImage: "trash", role: .destructive) {
				isDeleting = true
			}
		}
	}
}
