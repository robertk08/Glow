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
	
	@State private var recording: Recording?
	@State private var editing: Cue?
	
	var body: some View {
		let lists = looks.map { CueList($0, cues: cues, fixtures: fixtures, library: library) }
		let list = CueList(look, cues: cues, fixtures: fixtures, library: library)
		let held = look.cues(among: cues)
		let index = list.index(of: console.playback.cue(of: look.identifier))
		
		return NavigationStack {
			List {
				Section {
					ForEach(Array(held.enumerated()), id: \.element.identifier) { position, cue in
						Button {
							console.play(list, at: position)
						} label: {
							HStack(spacing: 12) {
								Text("\(position + 1)")
									.font(.subheadline.weight(.semibold))
									.monospacedDigit()
									.foregroundStyle(position == index ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
									.frame(minWidth: 22, alignment: .leading)
								
								VStack(alignment: .leading, spacing: 4) {
									Text(cue.title(at: position))
										.fontWeight(position == index ? .semibold : .regular)
										.lineLimit(2)
									
									Text(cue.timing)
										.font(.caption)
										.foregroundStyle(.secondary)
									
									if position == index, let fade = console.fades[look.identifier] {
										FadeBar(fade: fade, tint: look.tint.color ?? .accentColor)
											.padding(.vertical, 2)
									}
								}
								
								Spacer()
								
								if position == index {
									Image(systemName: "play.fill")
										.foregroundStyle(.tint)
								}
							}
							.contentShape(.rect)
						}
						.buttonStyle(.plain)
						.tint(look.tint.color)
						.listRowBackground(position == index ? (look.tint.color ?? .accentColor).opacity(0.14) : nil)
						.accessibilityAddTraits(position == index ? .isSelected : [])
						.swipeActions(edge: .leading) {
							Button("Edit", systemImage: "slider.horizontal.3") {
								editing = cue
							}
							.tint(.indigo)
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
							
							Button("Add Cue After", systemImage: "text.insert") {
								recording = Recording(.cue(look, after: cue), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues)
							}
							
							Button("Update Cue", systemImage: "arrow.triangle.2.circlepath") {
								Recording(.into(cue), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues).update(context: context)
							}
							.disabled(console.active.isEmpty)
							
							Button("Store into Cue", systemImage: "square.and.arrow.down") {
								recording = Recording(.into(cue), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues)
							}
							
							Button("Delete Cue", systemImage: "trash", role: .destructive) {
								context.delete(cue)
							}
						}
					}
					.onMove { console.move($0, to: $1, among: held, sortIndex: \.sortIndex) }
					
					Button("Build Cues", systemImage: "plus") {
						console.selection.building = look.identifier
						dismiss()
					}
				} header: {
					Text("Cues")
				} footer: {
					Text(held.count > 1 ? "Tap a cue to jump to it. After the last cue the next tap starts again at the first. The arrow keys or a presentation clicker step through them too." : "Add a cue and this scene steps through them, one tap at a time.")
				}
				
				Section {
					NavigationLink {
						SceneSettings(look: look)
					} label: {
						Label("Scene Settings", systemImage: "slider.horizontal.3")
					}
				} footer: {
					Text("Name, icon and colour, what a tap on the tile does and which buttons sit on it.")
				}
			}
			.safeAreaBar(edge: .top) {
				HStack(spacing: 10) {
					if held.count > 1 {
						Button("Back", systemImage: "backward.end.fill") {
							console.back(list)
						}
						.labelStyle(.iconOnly)
						.keyboardShortcut(.leftArrow, modifiers: [])
						.disabled(index == nil)
						
						Button {
							console.go(list)
						} label: {
							Label(index == nil ? "Start" : "Next Cue", systemImage: "forward.end.fill")
								.frame(maxWidth: .infinity)
						}
						.buttonStyle(.glassProminent)
						.keyboardShortcut(.rightArrow, modifiers: [])
						
						Button("Turn Off", systemImage: "stop.fill") {
							console.toggle(list, among: lists)
						}
						.labelStyle(.iconOnly)
						.disabled(index == nil)
					} else {
						Button {
							console.toggle(list, among: lists)
						} label: {
							Label(index == nil ? "Turn On" : "Turn Off", systemImage: index == nil ? "play.fill" : "stop.fill")
								.frame(maxWidth: .infinity)
						}
						.buttonStyle(.glassProminent)
					}
				}
				.lineLimit(1)
				.buttonStyle(.glass)
				.buttonBorderShape(.capsule)
				.controlSize(.large)
				.padding(.horizontal)
				.padding(.bottom, 8)
			}
			.navigationTitle(look.name)
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				if held.count > 1 {
					ToolbarItem(placement: .topBarLeading) {
						EditButton()
					}
				}
				
				if isSheet {
					ToolbarItem(placement: .topBarTrailing) {
						Button(role: .close) { dismiss() }
					}
				}
			}
			.sheet(item: $recording) { recording in
				StoreView(recording: recording)
			}
			.sheet(item: $editing) { cue in
				CueEditView(cue: cue, position: held.firstIndex { $0.identifier == cue.identifier } ?? 0)
			}
			.sensoryFeedback(.selection, trigger: console.playback)
			.onChange(of: looks.contains { $0.identifier == look.identifier }) {
				dismiss()
			}
		}
	}
}

private struct SceneSettings: View {
	@Environment(\.modelContext) private var context
	@Environment(\.dismiss) private var dismiss
	@Query(sort: \Cue.sortIndex) private var cues: [Cue]
	
	@Bindable var look: Look
	
	@State private var isDeleting = false
	
	var body: some View {
		Form {
			Section {
				TextField("Name", text: $look.name)
					.autocorrectionDisabled()
			}
			
			Section {
				Picker("A Tap", selection: $look.tap) {
					ForEach(SceneAction.taps) { action in
						Text(action.tapName)
							.tag(action)
					}
				}
				
				ForEach(SceneAction.allCases) { action in
					Toggle(isOn: Binding { look.buttons.contains(action) } set: { look.shows(action, $0) }) {
						Label(action.name, systemImage: action.symbol)
					}
				}
			} header: {
				Text("On the Tile")
			} footer: {
				Text("A tile with buttons is twice as wide. Everything else is in its menu.")
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
						dismiss()
					}
				} message: {
					Text("The lights stay as they are.")
				}
			}
		}
		.navigationTitle("Scene Settings")
		.navigationBarTitleDisplayMode(.inline)
	}
}
