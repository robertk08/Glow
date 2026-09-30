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
	@State private var isDeleting = false
	@State private var isCustomizing = false
	
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
		
		NavigationStack {
			Group {
				if held.isEmpty {
					ContentUnavailableView {
						Label("No Cues Yet", systemImage: look.symbol)
					} actions: {
						Button("Add Cues", systemImage: "plus") {
							console.selection.building = look.identifier
							console.selection.isSceneOpen = false
						}
						.buttonStyle(.glassProminent)
						.controlSize(.large)
					}
				} else {
					ScrollViewReader { proxy in
						List {
							ForEach(Array(held.enumerated()), id: \.element.identifier) { position, cue in
								Button {
									if editMode.isEditing {
										editing = cue
									} else {
										console.selection.arm(cue.identifier, of: look.identifier)
									}
								} label: {
									CueRow(list: list, position: position, isLive: position == index, isNext: position == upcoming, isArmed: armed == cue.identifier, fade: fade, tint: tint)
								}
								.buttonStyle(.plain)
								.id(cue.identifier)
								.listRowBackground(position == index ? tint.opacity(0.14) : nil)
								.accessibilityAddTraits(position == index ? .isSelected : [])
								.accessibilityValue(position == upcoming ? "Next" : "")
								.accessibilityHint(editMode.isEditing ? "Edits it." : "Makes it the next cue.")
								.swipeActions(edge: .leading) {
									Button("Edit", systemImage: "slider.horizontal.3") {
										editing = cue
									}
									.tint(tint)
								}
								.swipeActions(edge: .trailing) {
									Button("Delete", systemImage: "trash", role: .destructive) {
										console.delete(cue, from: list, context: context)
									}
								}
								.contextMenu {
									Button("Play Now", systemImage: "play.fill") {
										console.play(list, at: position)
									}
									
									Button("Edit", systemImage: "slider.horizontal.3") {
										editing = cue
									}
									
									Button("Add Cue After", systemImage: "text.insert") {
										console.play(list, at: position)
										console.selection.building = look.identifier
										console.selection.isSceneOpen = false
									}
									
									if console.canUpdate(cue) {
										Button("Update Cue", systemImage: "arrow.triangle.2.circlepath") {
											Recording(.into(cue), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues).store(context: context)
										}
									}
									
									Button("Delete Cue", systemImage: "trash", role: .destructive) {
										console.delete(cue, from: list, context: context)
									}
								}
							}
							.onMove { console.move($0, to: $1, among: held, sortIndex: \.sortIndex) }
							
							Button {
								console.selection.building = look.identifier
								console.selection.isSceneOpen = false
							} label: {
								Label("Add Cues", systemImage: "plus")
									.foregroundStyle(tint)
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
					if !held.isEmpty {
						Transport(look: look, list: list)
					}
					
					if !isSheet {
						MasterBar(isRaised: true)
					}
				}
			}
			.navigationTitle(look.name)
			.navigationBarTitleDisplayMode(.inline)
			.environment(\.editMode, $editMode)
			.toolbar {
				if isSheet {
					ToolbarItem(placement: .topBarLeading) {
						Button(role: .close) { dismiss() }
					}
				}
				
				if let index, !editMode.isEditing, console.canUpdate(held[index]) {
					ToolbarItem(placement: .topBarTrailing) {
						Button("Update \(index + 1)") {
							Recording(.into(held[index]), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues).store(context: context)
						}
						.buttonStyle(.glassProminent)
						.tint(tint)
					}
					
					ToolbarSpacer(.fixed, placement: .topBarTrailing)
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
						Menu {
							Button("Customize", systemImage: "slider.horizontal.3") {
								isCustomizing = true
							}
							
							Button("Duplicate Scene", systemImage: "plus.square.on.square") {
								look.duplicate(with: cues, among: looks, context: context)
							}
							
							Button("Delete Scene", systemImage: "trash", role: .destructive) {
								isDeleting = true
							}
						} label: {
							Label("More", systemImage: "ellipsis")
						}
					}
				}
			}
			.sheet(item: $editing) { cue in
				CueEditView(cue: cue)
			}
			.sheet(isPresented: $isCustomizing) {
				SceneSettings(look: look)
			}
			.confirmationDialog("Delete \(look.name)?", isPresented: $isDeleting, titleVisibility: .visible) {
				Button("Delete Scene", role: .destructive) {
					console.remove(look, with: cues, context: context)
				}
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
		let detail = list.detail(at: position)
		
		HStack(alignment: .firstTextBaseline, spacing: 12) {
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
				
				Group {
					if isLive {
						CueStatus(fade: fade, follow: cue.follow) {
							if !detail.isEmpty {
								Text(detail)
							}
						}
					} else if !detail.isEmpty {
						Text(detail)
					}
				}
				.font(.subheadline)
				.foregroundStyle(.secondary)
				
				if isLive, cue.fade + cue.delay > 0 {
					FadeBar(fade: fade, tint: tint)
						.padding(.vertical, 2)
				}
			}
			
			Spacer(minLength: 8)
			
			if isNext {
				Text("Next")
					.font(.caption.weight(.semibold))
					.foregroundStyle(isArmed ? AnyShapeStyle(.white) : AnyShapeStyle(tint))
					.padding(.horizontal, 8)
					.padding(.vertical, 3)
					.background(isArmed ? tint : tint.opacity(0.15), in: .capsule)
			}
			
			if cue.fade > 0 {
				Text(CueList.seconds(cue.fade))
					.foregroundStyle(.secondary)
					.monospacedDigit()
			}
		}
		.contentShape(.rect)
		.accessibilityElement(children: .combine)
		.accessibilityLabel(isLive ? "Live, \(list.heading(at: position))" : list.heading(at: position))
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
		let isAtEnd = steps && upcoming == nil
		
		GlassEffectContainer(spacing: 12) {
			HStack(spacing: 12) {
				if steps {
					Button {
						console.back(list)
					} label: {
						Image(systemName: SceneAction.back.symbol)
							.frame(width: height, height: height)
							.glassEffect(.regular.interactive(index != nil), in: .circle)
					}
					.accessibilityLabel("Back")
					.keyboardShortcut(.leftArrow, modifiers: [])
					.disabled(index == nil)
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
								}
								.font(.caption)
								.opacity(0.85)
							}
						} else {
							Label(SceneAction.toggle.name(isOn: index != nil), systemImage: SceneAction.toggle.symbol(isOn: index != nil))
								.contentTransition(.symbolEffect(.replace))
						}
					}
					.foregroundStyle(isAtEnd ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
					.padding(.horizontal)
					.frame(maxWidth: .infinity)
					.frame(height: height)
					.glassEffect(.regular.tint(isAtEnd ? nil : tint).interactive(!isAtEnd), in: .capsule)
				}
				.keyboardShortcut(.rightArrow, modifiers: [])
				.disabled(isAtEnd)
				
				if steps {
					Button {
						console.toggle(list)
					} label: {
						Image(systemName: "stop.fill")
							.frame(width: height, height: height)
							.glassEffect(.regular.interactive(index != nil), in: .circle)
					}
					.accessibilityLabel("Turn Off")
					.disabled(index == nil)
				}
			}
		}
		.buttonStyle(.plain)
		.font(.headline)
		.foregroundStyle(index == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
		.lineLimit(1)
		.padding(.horizontal)
		.padding(.vertical, 8)
	}
}
