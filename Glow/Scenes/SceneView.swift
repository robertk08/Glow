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
	@State private var isDeleting = false
	
	var body: some View {
		let lists = looks.map { CueList($0, cues: cues, fixtures: fixtures, library: library) }
		let list = CueList(look, cues: cues, fixtures: fixtures, library: library)
		let held = look.cues(among: cues)
		let index = list.index(of: console.playback.cue(of: look.identifier))
		let current = index.map { held[$0] }
		
		return NavigationStack {
			List {
				Section {
					HStack(spacing: 10) {
						if held.count > 1 {
							Button("Back", systemImage: "backward.end.fill") {
								console.back(list)
							}
							.labelStyle(.iconOnly)
							.disabled(index.flatMap(list.previous(before:)) == nil)
							
							Button {
								console.go(list)
							} label: {
								Label(index == nil ? "Start" : "Next Cue", systemImage: "forward.end.fill")
									.frame(maxWidth: .infinity)
							}
							.buttonStyle(.glassProminent)
							.disabled(list.next(after: index) == nil)
							
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
					.listRowBackground(Color.clear)
					.listRowSeparator(.hidden)
				}
				
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
								
								VStack(alignment: .leading, spacing: 1) {
									Text(cue.title(at: position))
										.lineLimit(2)
									
									Text(Cue.seconds(cue.fade))
										.font(.caption)
										.foregroundStyle(.secondary)
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
							
							Button("Store into Cue", systemImage: "square.and.arrow.down") {
								recording = Recording(.into(cue), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues)
							}
							
							Button("Delete Cue", systemImage: "trash", role: .destructive) {
								context.delete(cue)
							}
						}
					}
					.onMove { console.move($0, to: $1, among: held, sortIndex: \.sortIndex) }
					
					Button("Add Cue", systemImage: "plus") {
						recording = Recording(.cue(look, after: current), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues)
					}
				} header: {
					Text("Cues")
				} footer: {
					Text(held.count > 1 ? "Tap a cue to jump to it. A new cue goes after the one on stage." : "Add a cue and this scene steps through them, one tap at a time.")
				}
				
				Section("Name") {
					TextField("Name", text: $look.name)
						.autocorrectionDisabled()
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
			.navigationTitle(look.name)
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					EditButton()
						.disabled(held.count < 2)
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
		}
	}
}
