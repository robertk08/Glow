import SwiftData
import SwiftUI

struct SceneTile: View {
	@Environment(Console.self) private var console
	@Environment(\.modelContext) private var context
	@Environment(\.horizontalSizeClass) private var sizeClass
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	@Query(sort: \Cue.sortIndex) private var cues: [Cue]
	
	let look: Look
	let list: CueList
	let arrangement: Arrangement
	
	@Binding var isEditing: Bool
	@Binding var customizing: Look?
	
	@State private var isDeleting = false
	@State private var size = CGSize.zero
	
	var body: some View {
		if !look.isGone {
			content
		}
	}
	
	@ViewBuilder private var content: some View {
		Group {
			if isEditing {
				SceneFace(look: look, list: list)
					.onTapGesture {
						customizing = look
					}
					.gesture(HoldDrag { point in
						arrangement.lift(look.identifier, at: point, among: looks)
						arrangement.drag(to: point)
					} ended: {
						arrangement.drop(among: looks, console: console)
					})
					.accessibilityAddTraits(.isButton)
					.accessibilityHint("Customizes it.")
			} else {
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
			}
		}
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
				
				if isEditing {
					Image(systemName: "slider.horizontal.3")
						.font(.body.weight(.semibold))
						.foregroundStyle(.secondary)
						.frame(width: 44, height: 44)
						.allowsHitTesting(false)
						.transition(.scale.combined(with: .opacity))
				} else if list.cues.count > 1 {
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
					.transition(.scale.combined(with: .opacity))
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
		.alert("Delete \(look.name)?", isPresented: $isDeleting) {
			Button("Cancel", role: .cancel) {}
			
			Button("Delete Scene", role: .destructive) {
				console.remove(look, with: cues, context: context)
			}
		}
		.onGeometryChange(for: CGRect.self) { $0.frame(in: .named("tiles")) } action: { frame in
			size = frame.size
			arrangement.frames[look.identifier] = frame
		}
		.opacity(arrangement.lifted == look.identifier ? 0 : 1)
		.layoutValue(key: TileSpan.self, value: look.size)
		.animation(.snappy, value: isEditing)
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
				isEditing = true
			}
			
			Button("Delete Scene", systemImage: "trash", role: .destructive) {
				isDeleting = true
			}
		}
	}
}

private struct HoldDrag: UIGestureRecognizerRepresentable {
	let moved: (CGPoint) -> Void
	let ended: () -> Void
	
	func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
		let recognizer = UILongPressGestureRecognizer()
		recognizer.minimumPressDuration = 0.3
		return recognizer
	}
	
	func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
		switch recognizer.state {
		case .began, .changed: moved(context.converter.location(in: .named("tiles")))
		case .ended, .cancelled, .failed: ended()
		default: break
		}
	}
}
