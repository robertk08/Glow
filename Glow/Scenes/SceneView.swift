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
		let next = index.flatMap { list.next(after: $0) }
		let tint = look.tint.color ?? .accentColor
		
		NavigationStack {
			Group {
				if held.isEmpty {
					ContentUnavailableView {
						Label("No Cues Yet", systemImage: look.symbol)
					} description: {
						Text("Set the lights, store a cue, change them and store the next.")
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
										
										Text(cue.timing)
											.font(.caption)
											.foregroundStyle(.secondary)
										
										if position == index, let fade = console.fades[look.identifier] {
											FadeBar(fade: fade, tint: tint)
												.padding(.vertical, 2)
										}
									}
									
									Spacer(minLength: 8)
									
									if position == next, next != index {
										Text("Next")
											.font(.caption.weight(.medium))
											.foregroundStyle(.secondary)
									}
								}
								.contentShape(.rect)
							}
							.buttonStyle(.plain)
							.listRowBackground(position == index ? tint.opacity(0.14) : nil)
							.accessibilityAddTraits(position == index ? .isSelected : [])
							.swipeActions(edge: .leading) {
								Button("Update", systemImage: "arrow.triangle.2.circlepath") {
									Recording(.into(cue), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues).update(context: context)
								}
								.tint(tint)
								.disabled(!console.hasProgrammer)
							}
							.swipeActions(edge: .trailing) {
								Button("Delete", systemImage: "trash", role: .destructive) {
									context.delete(cue)
								}
							}
							.contextMenu {
								Button("Edit Cue", systemImage: "slider.horizontal.3") {
									editing = cue
								}
								
								Button("Update Cue", systemImage: "arrow.triangle.2.circlepath") {
									Recording(.into(cue), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues).update(context: context)
								}
								.disabled(!console.hasProgrammer)
								
								Button("Add Cue After", systemImage: "text.insert") {
									console.play(list, at: position)
									console.selection.building = look.identifier
									console.selection.isSceneOpen = false
								}
								
								Button("Delete Cue", systemImage: "trash", role: .destructive) {
									context.delete(cue)
								}
							}
						}
						.onMove { console.move($0, to: $1, among: held, sortIndex: \.sortIndex) }
						
						Button {
							console.selection.building = look.identifier
							console.selection.isSceneOpen = false
						} label: {
							Label("Add Cues", systemImage: "plus")
						}
						.tint(tint)
						
						SceneSettings(look: look)
					}
					.scrollEdgeEffectStyle(.hard, for: .bottom)
					.safeAreaBar(edge: .bottom) {
						Transport(look: look, list: list, lists: lists)
							.tint(tint)
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
			.sheet(item: $editing) { cue in
				CueEditView(cue: cue, position: held.firstIndex { $0.identifier == cue.identifier } ?? 0)
			}
			.confirmationDialog("Delete \(look.name)?", isPresented: $isDeleting, titleVisibility: .visible) {
				Button("Delete Scene", role: .destructive) {
					look.remove(with: cues, context: context)
				}
			} message: {
				Text("The lights stay as they are.")
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
	
	let look: Look
	let list: CueList
	let lists: [CueList]
	
	var body: some View {
		let index = list.index(of: console.playback.cue(of: look.identifier))
		
		HStack(spacing: 12) {
			if list.cues.count > 1 {
				Button("Back", systemImage: "backward.end.fill") {
					console.back(list)
				}
				.foregroundStyle(index == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
				.buttonStyle(.glass)
				.buttonBorderShape(.circle)
				.labelStyle(.iconOnly)
				.keyboardShortcut(.leftArrow, modifiers: [])
				.disabled(index == nil)
				
				Button {
					console.go(list)
				} label: {
					Label(index == nil ? "Start" : "Next Cue", systemImage: "forward.end.fill")
						.foregroundStyle(.white)
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.glassProminent)
				.keyboardShortcut(.rightArrow, modifiers: [])
				
				Button("Turn Off", systemImage: "stop.fill") {
					console.toggle(list, among: lists)
				}
				.foregroundStyle(index == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
				.buttonStyle(.glass)
				.buttonBorderShape(.circle)
				.labelStyle(.iconOnly)
				.disabled(index == nil)
			} else {
				Button {
					console.toggle(list, among: lists)
				} label: {
					Label(index == nil ? "Turn On" : "Turn Off", systemImage: "power")
						.foregroundStyle(.white)
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.glassProminent)
			}
		}
		.font(.headline)
		.controlSize(.extraLarge)
		.lineLimit(1)
		.padding(.horizontal)
		.padding(.bottom, 8)
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
					Text(action.tapName)
						.tag(action)
				}
			}
			
			ForEach(look.buttons + SceneAction.allCases.filter { !look.buttons.contains($0) }) { action in
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
				.disabled(!isOn && look.buttons.count >= Look.buttonLimit)
				.accessibilityAddTraits(isOn ? .isSelected : [])
				.moveDisabled(!isOn)
			}
			.onMove { from, to in
				var order = look.buttons + SceneAction.allCases.filter { !look.buttons.contains($0) }
				let chosen = Set(look.buttons)
				order.move(fromOffsets: from, toOffset: to)
				look.buttons = order.filter(chosen.contains)
			}
		} header: {
			Text("Tile")
		} footer: {
			Text("Tick up to three buttons for the tile. Edit puts them in order. Everything else is in the tile's menu.")
		}
		.animation(.snappy, value: look.buttons)
		
		Section("Name and Icon") {
			TextField("Name", text: $look.name)
				.autocorrectionDisabled()
			
			AppearancePicker(symbol: Binding { look.symbol } set: { look.symbolOverride = $0 }, tint: $look.tint)
		}
	}
}
