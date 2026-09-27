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
	@State private var isShowingSettings = false
	@State private var isDeleting = false
	
	var body: some View {
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
												.foregroundStyle(.tint)
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
					}
					.tint(tint)
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
				
				ToolbarItem(placement: .topBarTrailing) {
					if editMode.isEditing {
						Button("Done", role: .confirm) {
							editMode = .inactive
						}
					} else {
						Menu {
							Button("Scene Settings", systemImage: "slider.horizontal.3") {
								isShowingSettings = true
							}
							
							Button("Add Cues", systemImage: "plus") {
								console.selection.building = look.identifier
								console.selection.isSceneOpen = false
							}
							
							if held.count > 1 {
								Button("Reorder Cues", systemImage: "arrow.up.arrow.down") {
									editMode = .active
								}
							}
							
							Divider()
							
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
			.navigationDestination(isPresented: $isShowingSettings) {
				SceneSettings(look: look)
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
				.foregroundStyle(.primary)
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
				.foregroundStyle(.primary)
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
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.modelContext) private var context
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	@Query(sort: \Cue.sortIndex) private var cues: [Cue]
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	@Bindable var look: Look
	
	@State private var isDeleting = false
	
	var body: some View {
		let lists = looks.map { CueList($0, cues: cues, fixtures: fixtures, library: library) }
		
		Form {
			Section {
				TextField("Name", text: $look.name)
					.autocorrectionDisabled()
				
				Picker("Tap", selection: $look.tap) {
					ForEach(SceneAction.taps) { action in
						Text(action.tapName)
							.tag(action)
					}
				}
			} header: {
				SceneTile(look: look, list: CueList(look, cues: cues, fixtures: fixtures, library: library), lists: lists, recording: .constant(nil), deleting: .constant(nil))
					.allowsHitTesting(false)
					.containerRelativeFrame(.horizontal) { width, _ in
						look.buttons.isEmpty ? (width - 44) / 2 : width - 32
					}
					.frame(maxWidth: .infinity)
					.padding(.bottom, 20)
					.textCase(nil)
					.foregroundStyle(.primary)
					.font(.body)
					.accessibilityHidden(true)
			}
			
			Section {
				ForEach(look.buttons + SceneAction.allCases.filter { !look.buttons.contains($0) }) { action in
					let isOn = look.buttons.contains(action)
					
					Button {
						look.shows(action, !isOn)
					} label: {
						HStack(spacing: 16) {
							Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
								.font(.title3)
								.foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
							
							Label(action.name, systemImage: action.symbol)
								.foregroundStyle(isOn ? .primary : .secondary)
							
							Spacer(minLength: 0)
						}
						.contentShape(.rect)
					}
					.buttonStyle(.plain)
					.disabled(!isOn && look.buttons.count >= Look.buttonLimit)
					.accessibilityAddTraits(isOn ? .isSelected : [])
				}
				.onMove { from, to in
					var order = look.buttons + SceneAction.allCases.filter { !look.buttons.contains($0) }
					let chosen = Set(look.buttons)
					order.move(fromOffsets: from, toOffset: to)
					look.buttons = order.filter(chosen.contains)
				}
			} header: {
				Text("Buttons")
			} footer: {
				Text("Choose up to three for the tile and drag them into order. Everything else is in its menu.")
			}
			
			Section("Icon") {
				AppearancePicker(symbol: Binding { look.symbol } set: { look.symbolOverride = $0 }, tint: $look.tint)
			}
			
			Section {
				Button("Delete Scene", role: .destructive) {
					isDeleting = true
				}
				.confirmationDialog("Delete \(look.name)?", isPresented: $isDeleting, titleVisibility: .visible) {
					Button("Delete Scene", role: .destructive) {
						look.remove(with: cues, context: context)
					}
				} message: {
					Text("The lights stay as they are.")
				}
			}
		}
		.environment(\.editMode, .constant(.active))
		.animation(.snappy, value: look.buttons)
		.navigationTitle("Scene Settings")
		.navigationBarTitleDisplayMode(.inline)
	}
}
