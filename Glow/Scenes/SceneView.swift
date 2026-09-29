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
	@State private var renaming: Cue?
	@State private var label = ""
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
									console.selection.arm(cue.identifier, of: look.identifier)
								} label: {
									HStack(spacing: 14) {
										Group {
											if position == index {
												Image(systemName: "play.fill")
													.foregroundStyle(tint)
													.accessibilityLabel("Live")
											} else {
												Text("\(position + 1)")
													.foregroundStyle(.secondary)
											}
										}
										.font(.subheadline.weight(.semibold))
										.monospacedDigit()
										.frame(width: 28)
										
										VStack(alignment: .leading, spacing: 3) {
											Text(cue.title(at: position))
												.fontWeight(position == index ? .semibold : .regular)
												.lineLimit(2)
											
											if position == index {
												CueStatus(text: cue.timing, fade: fade, follow: cue.follow)
													.font(.caption)
													.foregroundStyle(.secondary)
												
												if cue.fade + cue.delay > 0 {
													FadeBar(fade: fade, tint: tint)
														.padding(.vertical, 2)
												}
											} else if !cue.timing.isEmpty {
												Text(cue.timing)
													.font(.caption)
													.foregroundStyle(.secondary)
											}
										}
										
										Spacer(minLength: 8)
										
										if position == upcoming {
											Text("Next")
												.font(.caption.weight(.semibold))
												.foregroundStyle(armed == cue.identifier ? AnyShapeStyle(.white) : AnyShapeStyle(tint))
												.padding(.horizontal, 8)
												.padding(.vertical, 3)
												.background(armed == cue.identifier ? tint : tint.opacity(0.15), in: .capsule)
										}
									}
									.contentShape(.rect)
								}
								.buttonStyle(.plain)
								.id(cue.identifier)
								.listRowBackground(position == index ? tint.opacity(0.14) : nil)
								.accessibilityAddTraits(position == index ? .isSelected : [])
								.accessibilityValue(position == upcoming ? "Next" : "")
								.accessibilityHint("Makes it the next cue.")
								.swipeActions(edge: .leading) {
									Button("Timing", systemImage: "slider.horizontal.3") {
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
									
									Button("Rename", systemImage: "pencil") {
										label = cue.label
										renaming = cue
									}
									
									Button("Timing and Lights", systemImage: "slider.horizontal.3") {
										editing = cue
									}
									
									Button("Add Cue After", systemImage: "text.insert") {
										console.play(list, at: position)
										console.selection.building = look.identifier
										console.selection.isSceneOpen = false
									}
									
									Button("Update Cue", systemImage: "arrow.triangle.2.circlepath") {
										Recording(.into(cue), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues).store(context: context)
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
			.alert("Rename Cue", isPresented: Binding { renaming != nil } set: { if !$0 { renaming = nil } }) {
				TextField("Name or short description", text: $label)
				
				Button("Cancel", role: .cancel) {}
				
				Button("Rename") {
					renaming?.label = label.trimmingCharacters(in: .whitespaces)
				}
			}
			.sheet(item: $editing) { cue in
				CueEditView(cue: cue, position: held.firstIndex { $0.identifier == cue.identifier } ?? 0)
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
		
		GlassEffectContainer(spacing: 12) {
			HStack(spacing: 12) {
				if steps {
					Button {
						console.back(list)
					} label: {
						Image(systemName: "backward.end.fill")
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
						if steps, let upcoming {
							VStack(spacing: 1) {
								Label("Go", systemImage: "forward.end.fill")
								
								Text(list.heading(at: upcoming))
									.font(.caption)
									.opacity(0.85)
									.contentTransition(.numericText())
							}
						} else {
							Label(index == nil ? "Turn On" : "Turn Off", systemImage: "power")
						}
					}
					.foregroundStyle(.white)
					.padding(.horizontal)
					.frame(maxWidth: .infinity)
					.frame(height: height)
					.glassEffect(.regular.tint(tint).interactive(), in: .capsule)
				}
				.keyboardShortcut(.rightArrow, modifiers: [])
				
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
