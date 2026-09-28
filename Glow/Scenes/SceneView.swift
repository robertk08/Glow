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
	
	var body: some View {
		if !look.isGone {
			content
		}
	}
	
	@ViewBuilder private var content: some View {
		let lists = looks.map { CueList($0, cues: cues, fixtures: fixtures, library: library) }
		let list = CueList(look, cues: cues, fixtures: fixtures, library: library)
		let held = look.cues(among: cues)
		let index = list.index(of: console.playback.cue(of: look.identifier))
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
					List {
						ForEach(Array(held.enumerated()), id: \.element.identifier) { position, cue in
							Button {
								console.play(list, at: position)
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
									.frame(width: 24)
									
									VStack(alignment: .leading, spacing: 3) {
										Text(cue.title(at: position))
											.fontWeight(position == index ? .semibold : .regular)
											.lineLimit(2)
										
										if !cue.timing.isEmpty {
											Text(cue.timing)
												.font(.caption)
												.foregroundStyle(.secondary)
										}
										
										if position == index, let fade = console.fades[look.identifier] {
											FadeBar(fade: fade, tint: tint)
												.padding(.vertical, 2)
										}
									}
									
									Spacer(minLength: 8)
								}
								.contentShape(.rect)
							}
							.buttonStyle(.plain)
							.listRowBackground(position == index ? tint.opacity(0.14) : nil)
							.accessibilityAddTraits(position == index ? .isSelected : [])
							.swipeActions(edge: .leading) {
								Button("Update", systemImage: "arrow.triangle.2.circlepath") {
									Recording(.into(cue), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues).store(context: context)
								}
								.tint(tint)
							}
							.swipeActions(edge: .trailing) {
								Button("Delete", systemImage: "trash", role: .destructive) {
									console.delete(cue, from: list, among: lists, context: context)
								}
							}
							.contextMenu {
								Button("Rename", systemImage: "pencil") {
									label = cue.label
									renaming = cue
								}
								
								Button("Timing and Lights", systemImage: "slider.horizontal.3") {
									editing = cue
								}
								
								Button("Update Cue", systemImage: "arrow.triangle.2.circlepath") {
									Recording(.into(cue), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues).store(context: context)
								}
								
								Button("Add Cue After", systemImage: "text.insert") {
									console.play(list, at: position)
									console.selection.building = look.identifier
									console.selection.isSceneOpen = false
								}
								
								Button("Delete Cue", systemImage: "trash", role: .destructive) {
									console.delete(cue, from: list, among: lists, context: context)
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
						
						SceneSettings(look: look)
					}
				}
			}
			.safeAreaBar(edge: .bottom) {
				VStack(spacing: 0) {
					if !held.isEmpty {
						Transport(look: look, list: list, lists: lists)
					}
					
					if !isSheet {
						MasterBar(isRaised: true)
							.padding(.bottom, 8)
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
			.confirmationDialog("Delete \(look.name)?", isPresented: $isDeleting, titleVisibility: .visible) {
				Button("Delete Scene", role: .destructive) {
					look.remove(with: cues, context: context)
				}
			}
			.sensoryFeedback(.selection, trigger: console.playback)
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
	let lists: [CueList]
	
	var body: some View {
		let index = list.index(of: console.playback.cue(of: look.identifier))
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
						console.toggle(list, among: lists)
					}
				} label: {
					Label(steps ? (index == nil ? "Start" : "Next Cue") : (index == nil ? "Turn On" : "Turn Off"), systemImage: steps ? "forward.end.fill" : "power")
						.foregroundStyle(.white)
						.frame(maxWidth: .infinity)
						.frame(height: height)
						.glassEffect(.regular.tint(tint).interactive(), in: .capsule)
				}
				.keyboardShortcut(.rightArrow, modifiers: [])
				
				if steps {
					Button {
						console.toggle(list, among: lists)
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

private struct SceneSettings: View {
	@Bindable var look: Look
	
	var body: some View {
		if !look.isGone {
			content
		}
	}
	
	@ViewBuilder private var content: some View {
		Section {
			Picker("Tap", selection: $look.tap) {
				ForEach(SceneAction.taps) { action in
					Text(action.name)
						.tag(action)
				}
			}
			
			ForEach(look.buttons + SceneAction.buttons.filter { !look.buttons.contains($0) }) { action in
				let isOn = look.buttons.contains(action)
				
				Button {
					look.shows(action, !isOn)
				} label: {
					HStack(spacing: 16) {
						Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
							.font(.title3)
							.foregroundStyle(isOn ? AnyShapeStyle(look.tint.color ?? .accentColor) : AnyShapeStyle(.tertiary))
						
						Label(action.name, systemImage: action.symbol)
							.foregroundStyle(isOn ? .primary : .secondary)
						
						Spacer(minLength: 0)
					}
					.contentShape(.rect)
				}
				.buttonStyle(.plain)
				.accessibilityAddTraits(isOn ? .isSelected : [])
				.moveDisabled(!isOn)
			}
			.onMove { from, to in
				var order = look.buttons + SceneAction.buttons.filter { !look.buttons.contains($0) }
				let chosen = Set(look.buttons)
				order.move(fromOffsets: from, toOffset: to)
				look.buttons = order.filter(chosen.contains)
			}
		} header: {
			Text("Tile")
		}
		.animation(.snappy, value: look.buttons)
		
		Section {
			DisclosureGroup {
				TextField("Name", text: $look.name)
					.autocorrectionDisabled()
				
				AppearancePicker(symbol: Binding { look.symbol } set: { look.symbolOverride = $0 }, tint: $look.tint)
			} label: {
				Label {
					Text("Name, Icon and Colour")
				} icon: {
					Image(systemName: look.symbol)
						.foregroundStyle(look.tint.color ?? .accentColor)
				}
			}
		}
	}
}
