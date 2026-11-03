import SwiftData
import SwiftUI

struct SceneView: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.modelContext) private var context
	@Environment(\.dismiss) private var dismiss
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	@Query(sort: \Cue.sortIndex) private var cues: [Cue]
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	@Bindable var look: Look
	
	var isSheet = false
	
	@State private var editing: Cue?
	@State private var editMode = EditMode.inactive
	@State private var deleting: String?
	@State private var isCustomizing = false
	@State private var chosen = Set<String>()
	@State private var isRetiming = false
	@State private var isDeletingChosen = false
	
	var body: some View {
		if !look.isGone {
			content
		}
	}
	
	@ViewBuilder private var content: some View {
		let list = CueList(look, cues: cues, fixtures: fixtures)
		let held = look.cues(among: cues)
		let index = list.index(of: console.playback.cue(of: look.identifier))
		let live = index.map { held[$0].identifier }
		let upcoming = held.count > 1 ? console.upcoming(list) : nil
		let armed = console.selection.armed[look.identifier]
		let fade = console.playback.fades[look.identifier]
		let tint = look.tint.color ?? .accentColor
		let picked = held.filter { chosen.contains($0.identifier) }
		
		NavigationStack {
			Group {
				if held.isEmpty {
					ContentUnavailableView {
						Label("No Cues Yet", systemImage: look.symbol)
					} actions: {
						Button("Add Cues", systemImage: "plus") {
							console.selection.build(look.identifier)
							console.selection.isSceneOpen = false
						}
						.buttonStyle(.glassProminent)
						.controlSize(.large)
					}
				} else {
					ScrollViewReader { proxy in
						List(selection: $chosen) {
							ForEach(Array(held.enumerated()), id: \.element.identifier) { position, cue in
								Button {
									if !editMode.isEditing {
										console.selection.arm(cue.identifier, of: look.identifier)
									} else if chosen.contains(cue.identifier) {
										chosen.remove(cue.identifier)
									} else {
										chosen.insert(cue.identifier)
									}
								} label: {
									CueRow(list: list, position: position, isLive: position == index, isNext: position == upcoming, isArmed: armed == cue.identifier, fade: fade, tint: tint)
								}
								.buttonStyle(.plain)
								.id(cue.identifier)
								.listRowBackground(position == index ? tint.opacity(0.14) : nil)
								.accessibilityAddTraits(position == index ? .isSelected : [])
								.accessibilityValue(position == upcoming ? "Next" : "")
								.accessibilityHint(editMode.isEditing ? "" : "Makes it the next cue.")
								.swipeActions(edge: .leading) {
									Button("Edit", systemImage: "slider.horizontal.3") {
										editing = cue
									}
									.tint(tint)
								}
								.swipeActions(edge: .trailing) {
									Button("Delete", systemImage: "trash") {
										deleting = cue.identifier
									}
									.tint(.red)
								}
								.contextMenu {
									Button("Play Now", systemImage: "play.fill") {
										console.play(list, at: position)
									}
									
									Button("Edit", systemImage: "slider.horizontal.3") {
										editing = cue
									}
									
									Button("Delete Cue", systemImage: "trash", role: .destructive) {
										deleting = cue.identifier
									}
								}
							}
							.onMove { console.move($0, to: $1, among: held, sortIndex: \.sortIndex) }
							
							if held.count > 1 {
								LoopRow(look: look, list: list, tint: tint)
							}
							
							Button {
								console.selection.build(look.identifier)
								console.selection.isSceneOpen = false
							} label: {
								Label("Add Cues", systemImage: "plus")
									.foregroundStyle(tint)
							}
						}
						.alert("Delete Cue \((held.firstIndex { $0.identifier == deleting } ?? 0) + 1)?", isPresented: Binding { deleting != nil } set: { if !$0 { deleting = nil } }, presenting: held.first { $0.identifier == deleting }) { cue in
							Button("Cancel", role: .cancel) {}
							
							Button("Delete", role: .destructive) {
								withAnimation {
									console.delete([cue], from: list, context: context)
								}
							}
						}
						.onAppear {
							if let live { proxy.scrollTo(live, anchor: .center) }
						}
						.onChange(of: live) {
							guard let live else { return }
							
							withAnimation {
								proxy.scrollTo(live, anchor: .center)
							}
						}
					}
				}
			}
			.safeAreaBar(edge: .bottom) {
				VStack(spacing: 0) {
					if editMode.isEditing {
						if !picked.isEmpty {
							ChosenBar(look: look, list: list, picked: picked, held: held, isRetiming: $isRetiming, isDeleting: $isDeletingChosen)
								.transition(.move(edge: .bottom).combined(with: .opacity))
						}
					} else if !held.isEmpty {
						Transport(look: look, list: list)
					}
					
					if !isSheet {
						MasterBar(isRaised: true)
					}
				}
			}
			.animation(.snappy(duration: 0.25), value: picked.isEmpty)
			.navigationTitle(editMode.isEditing && !picked.isEmpty ? "\(picked.count) Selected" : look.name)
			.navigationBarTitleDisplayMode(.inline)
			.environment(\.editMode, $editMode)
			.toolbar {
				if editMode.isEditing {
					ToolbarItem(placement: .topBarLeading) {
						Button(picked.count == held.count ? "Deselect All" : "Select All") {
							chosen = picked.count == held.count ? [] : Set(held.map(\.identifier))
						}
					}
				} else if isSheet {
					ToolbarItem(placement: .topBarLeading) {
						Button(role: .close) { dismiss() }
					}
				}
				
				if !held.isEmpty {
					ToolbarItem(placement: .topBarTrailing) {
						if editMode.isEditing {
							Button("Done", role: .confirm) {
								editMode = .inactive
							}
						} else {
							Button("Edit") {
								editMode = .active
							}
						}
					}
				}
				
				ToolbarSpacer(.fixed, placement: .topBarTrailing)
				
				ToolbarItem(placement: .topBarTrailing) {
					if !editMode.isEditing {
						Button("Customize", systemImage: "slider.horizontal.3") {
							isCustomizing = true
						}
					}
				}
			}
			.sheet(item: $editing) { cue in
				CueEditView(cue: cue)
			}
			.sheet(isPresented: $isRetiming) {
				CueTimingSheet(picked: picked)
			}
			.confirmationDialog(picked.count == 1 ? "Delete 1 Cue?" : "Delete \(picked.count) Cues?", isPresented: $isDeletingChosen, titleVisibility: .visible) {
				Button("Delete", role: .destructive) {
					withAnimation {
						console.delete(picked, from: list, context: context)
					}
					
					chosen = []
				}
			}
			.onChange(of: editMode.isEditing) {
				chosen = []
			}
			.sheet(isPresented: $isCustomizing) {
				SceneSettings(look: look)
			}
			.onChange(of: looks.contains { $0.identifier == look.identifier }) {
				dismiss()
			}
		}
	}
}

private struct CueRow: View {
	let list: CueList
	let position: Int
	let isLive: Bool
	let isNext: Bool
	let isArmed: Bool
	let fade: Fade?
	let tint: Color
	
	var body: some View {
		let cue = list.cues[position]
		
		HStack(alignment: .center, spacing: 12) {
			Text("\(position + 1)")
				.font(.body.weight(isLive ? .bold : .regular))
				.foregroundStyle(isLive ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
				.monospacedDigit()
				.frame(minWidth: 28, alignment: .trailing)
			
			VStack(alignment: .leading, spacing: 4) {
				Text(cue.label.isEmpty ? "Cue \(position + 1)" : cue.label)
					.fontWeight(isLive ? .semibold : .regular)
					.foregroundStyle(cue.label.isEmpty ? .secondary : .primary)
					.lineLimit(2)
					.alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
				
				if isLive {
					CueStatus(fade: fade, follow: cue.follow) {
						if cue.fade + cue.delay > 0 {
							FadeBar(fade: fade, tint: tint)
								.padding(.vertical, 5)
						}
					}
					.font(.subheadline)
					.foregroundStyle(.secondary)
				}
			}
			
			Spacer(minLength: 8)
			
			if isNext {
				Image(systemName: SceneAction.next.symbol)
					.font(.subheadline.weight(.semibold))
					.foregroundStyle(isArmed ? AnyShapeStyle(.white) : AnyShapeStyle(tint))
					.frame(width: 30, height: 30)
					.background(isArmed ? tint : .clear, in: .circle)
					.transition(.scale.combined(with: .opacity))
			}
			
			CueTimeline(delay: cue.delay, fade: cue.fade, follow: list.next(after: position) == nil ? nil : cue.follow)
				.font(.caption2)
				.foregroundStyle(isLive ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
		}
		.contentShape(.rect)
		.accessibilityElement(children: .combine)
		.accessibilityLabel(isLive ? "Live, \(list.heading(at: position))" : list.heading(at: position))
	}
}

private struct LoopRow: View {
	@Bindable var look: Look
	
	let list: CueList
	let tint: Color
	
	var body: some View {
		Button {
			look.loops.toggle()
		} label: {
			HStack(spacing: 12) {
				Image(systemName: "repeat")
					.font(.body.weight(.semibold))
					.frame(minWidth: 28, alignment: .trailing)
				
				Text(list.heading(at: 0))
					.strikethrough(!look.loops)
				
				Spacer(minLength: 0)
			}
			.foregroundStyle(look.loops ? AnyShapeStyle(tint) : AnyShapeStyle(.tertiary))
			.contentShape(.rect)
		}
		.buttonStyle(.plain)
		.accessibilityLabel("Loop")
		.accessibilityAddTraits(look.loops ? .isSelected : [])
		.animation(.snappy(duration: 0.25), value: look.loops)
		.sensoryFeedback(.selection, trigger: look.loops)
	}
}

private struct ChosenBar: View {
	@Environment(Console.self) private var console
	@Environment(\.modelContext) private var context
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	@Query(sort: \Cue.sortIndex) private var cues: [Cue]
	@ScaledMetric(relativeTo: .headline) private var height = 54
	
	let look: Look
	let list: CueList
	let picked: [Cue]
	let held: [Cue]
	
	@Binding var isRetiming: Bool
	@Binding var isDeleting: Bool
	
	var body: some View {
		GlassEffectContainer(spacing: 12) {
			HStack(spacing: 12) {
				Button("Timing", systemImage: "timer") {
					isRetiming = true
				}
				.frame(maxWidth: .infinity)
				
				Button("Duplicate", systemImage: "plus.square.on.square") {
					withAnimation {
						console.duplicate(picked, among: held, context: context)
					}
				}
				.frame(maxWidth: .infinity)
				
				if looks.count > 1 {
					Menu("Move to Scene", systemImage: "arrow.right.square") {
						ForEach(looks.filter { $0.identifier != look.identifier }) { other in
							Button(other.name, systemImage: other.symbol) {
								withAnimation {
									console.move(picked, from: list, to: other, among: cues)
								}
							}
						}
					}
					.frame(maxWidth: .infinity)
					
					Menu("Copy to Scene", systemImage: "doc.on.doc") {
						ForEach(looks.filter { $0.identifier != look.identifier }) { other in
							Button(other.name, systemImage: other.symbol) {
								console.copy(picked, to: other, among: cues, context: context)
							}
						}
					}
					.frame(maxWidth: .infinity)
				}
				
				Button("Delete", systemImage: "trash", role: .destructive) {
					isDeleting = true
				}
				.foregroundStyle(.red)
				.frame(maxWidth: .infinity)
			}
			.labelStyle(.iconOnly)
			.menuOrder(.fixed)
			.font(.title3)
			.frame(maxWidth: .infinity)
			.frame(height: height)
			.glassEffect(.regular, in: .capsule)
		}
		.buttonStyle(.plain)
		.padding(.horizontal)
		.padding(.vertical, 8)
	}
}

private struct Transport: View {
	@Environment(Console.self) private var console
	@ScaledMetric(relativeTo: .headline) private var height = 54
	
	let look: Look
	let list: CueList
	
	var body: some View {
		let index = list.index(of: console.playback.cue(of: look.identifier))
		let upcoming = console.upcoming(list)
		let tint = look.tint.color ?? .accentColor
		let steps = list.cues.count > 1
		let isOn = index != nil
		let canGoBack = index.flatMap(list.previous(before:)) != nil
		let isAtEnd = steps && upcoming == nil
		let isLit = isOn && !isAtEnd
		
		GlassEffectContainer(spacing: 12) {
			HStack(spacing: 12) {
				if steps {
					Button {
						console.back(list)
					} label: {
						Image(systemName: SceneAction.back.symbol)
							.foregroundStyle(canGoBack ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
							.frame(width: height, height: height)
							.glassEffect(.regular.interactive(canGoBack), in: .circle)
					}
					.accessibilityLabel("Back")
					.keyboardShortcut(.leftArrow, modifiers: [])
					.disabled(!canGoBack)
				}
				
				Button {
					if steps {
						console.go(list)
					} else {
						console.toggle(list)
					}
				} label: {
					Group {
						if steps {
							VStack(spacing: 1) {
								Label("Go", systemImage: SceneAction.next.symbol)
								
								CueStatus(fade: console.playback.fades[look.identifier], follow: index.flatMap { list.cues[$0].follow }) {
									Text(upcoming.map(list.heading(at:)) ?? "End")
										.contentTransition(.numericText())
								}
								.font(.caption)
								.opacity(0.85)
							}
						} else {
							Label(SceneAction.toggle.name(isOn: isOn), systemImage: SceneAction.toggle.symbol(isOn: isOn))
								.contentTransition(.symbolEffect(.replace))
						}
					}
					.foregroundStyle(isLit ? AnyShapeStyle(.white) : isAtEnd ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
					.padding(.horizontal)
					.frame(maxWidth: .infinity)
					.frame(height: height)
					.glassEffect(.regular.tint(isLit ? tint : nil).interactive(!isAtEnd), in: .capsule)
				}
				.keyboardShortcut(.rightArrow, modifiers: [])
				.disabled(isAtEnd)
				
				if steps {
					Button {
						console.toggle(list)
					} label: {
						Image(systemName: "stop.fill")
							.frame(width: height, height: height)
							.glassEffect(.regular.interactive(isOn), in: .circle)
					}
					.accessibilityLabel("Turn Off")
					.disabled(!isOn)
				}
			}
		}
		.buttonStyle(.plain)
		.font(.headline)
		.foregroundStyle(isOn ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
		.lineLimit(1)
		.padding(.horizontal)
		.padding(.vertical, 8)
		.animation(.snappy(duration: 0.25), value: [isOn, isAtEnd, canGoBack])
		.animation(.snappy(duration: 0.3), value: upcoming)
	}
}
