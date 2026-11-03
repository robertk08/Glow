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
				SceneFace(look: look, list: list, size: arrangement.size(of: look))
					.onTapGesture {
						customizing = look
					}
					.onDrag {
						arrangement.pick(look.identifier)
					} preview: {
						SceneFace(look: look, list: list)
							.overlay {
								TileControls(look: look, list: list, isEditing: true)
							}
							.frame(width: size.width, height: size.height)
							.background(.background, in: .rect(cornerRadius: 24, style: .continuous))
							.environment(console)
					}
					.contentShape(.dragPreview, .rect(cornerRadius: 24, style: .continuous))
					.modifier(DragStart(arrangement: arrangement, looks: looks))
					.accessibilityAddTraits(.isButton)
					.accessibilityHint("Customizes it.")
					.overlay(alignment: .bottomTrailing) {
						StretchHandle()
							.gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("tiles")).onChanged { drag in
								arrangement.stretch(look.identifier, by: drag.translation, among: looks)
							}.onEnded { _ in
								arrangement.settle(among: looks)
							})
							.accessibilityLabel("Size")
							.accessibilityValue(arrangement.size(of: look).name)
							.accessibilityAdjustableAction { direction in
								let sizes = TileSize.allCases
								let index = sizes.firstIndex(of: look.size) ?? 0
								let next = direction == .increment ? min(index + 1, sizes.count - 1) : max(index - 1, 0)
								arrangement.resize(look, to: sizes[next], among: looks)
							}
							.transition(.scale.combined(with: .opacity))
					}
					.overlay(alignment: .topLeading) {
						Button("Delete Scene", systemImage: "minus") {
							isDeleting = true
						}
						.labelStyle(.iconOnly)
						.font(.system(size: 13, weight: .heavy))
						.foregroundStyle(.primary)
						.frame(width: 26, height: 26)
						.glassEffect(.regular.interactive(), in: .circle)
						.frame(width: 44, height: 44)
						.contentShape(.circle)
						.offset(x: -16, y: -16)
						.buttonStyle(.plain)
						.transition(.scale.combined(with: .opacity))
					}
					.modifier(Wiggle(size: arrangement.size(of: look), phase: Double(abs(look.identifier.hashValue % 100)) / 100, isStill: arrangement.stretched?.scene == look.identifier))
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
			SceneFace(look: look, list: list)
				.overlay {
					TileControls(look: look, list: list)
				}
				.frame(width: size.width, height: size.height)
				.environment(console)
		})
		.overlay {
			TileControls(look: look, list: list, isEditing: isEditing)
		}
		.confirmationDialog("Delete \(look.name)?", isPresented: $isDeleting, titleVisibility: .visible) {
			Button("Delete Scene", role: .destructive) {
				console.remove(look, with: cues, context: context)
			}
		}
		.onGeometryChange(for: CGRect.self) { $0.frame(in: .named("tiles")) } action: { frame in
			size = frame.size
			arrangement.frames[look.identifier] = frame
		}
		.opacity(arrangement.lifted == look.identifier ? 0 : 1)
		.layoutValue(key: TileSpan.self, value: arrangement.size(of: look))
		.layoutValue(key: TileSlot.self, value: arrangement.slot(of: look))
		.animation(.snappy(duration: 0.3), value: isEditing)
	}
}

private struct StretchHandle: View {
	var body: some View {
		Path { path in
			path.move(to: CGPoint(x: 41.5, y: 10))
			path.addArc(center: CGPoint(x: 20, y: 20), radius: 21.5, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
			path.addLine(to: CGPoint(x: 10, y: 41.5))
		}
		.stroke(.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
		.shadow(color: .black.opacity(0.35), radius: 1.5)
		.frame(width: 44, height: 44)
		.contentShape(.rect)
	}
}

private struct DragStart: ViewModifier {
	let arrangement: Arrangement
	let looks: [Look]
	
	func body(content: Content) -> some View {
		if #available(iOS 27, *) {
			content
				.onDragSessionUpdated { session in
					switch session.phase {
					case .initial: arrangement.hold(at: session.location, among: looks)
					case .active: arrangement.follow(session.location)
					case let .ended(operation): arrangement.end(dropped: operation == .move, among: looks)
					default: break
					}
				}
		} else {
			content
		}
	}
}

private struct Wiggle: ViewModifier {
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	
	let size: TileSize
	let phase: Double
	let isStill: Bool
	
	func body(content: Content) -> some View {
		let isPaused = reduceMotion || isStill
		
		TimelineView(.animation(paused: isPaused)) { context in
			content
				.rotationEffect(.degrees(isPaused ? 0 : sin((context.date.timeIntervalSinceReferenceDate + phase) * 17) * (size == .small ? 0.5 : 0.2)))
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
				isEditing = true
			}
			
			Button("Delete Scene", systemImage: "trash", role: .destructive) {
				isDeleting = true
			}
		}
	}
}
