import SwiftData
import SwiftUI

struct CueListView: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.modelContext) private var context
	@Environment(\.dismiss) private var dismiss
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	@Query(sort: \Cue.number) private var cues: [Cue]
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	@Bindable var look: Look
	
	@State private var recording: Recording?
	@State private var editing: Cue?
	@State private var isRenaming = false
	@State private var renamed = ""
	@State private var isDeleting = false
	
	var body: some View {
		let list = CueList(look, cues: cues, fixtures: fixtures, library: library)
		let held = look.cues(among: cues)
		let index = list.index(of: console.activeCue)
		let next = list.upcoming(after: index)
		
		List {
			ForEach(Array(held.enumerated()), id: \.element.identifier) { position, cue in
				Button {
					console.play(list, at: position)
				} label: {
					CueRow(cue: cue, spots: list.spots(at: position), isCurrent: position == index, isNext: position == next && position != index)
				}
				.buttonStyle(.plain)
				.listRowBackground(position == index ? Color.accentColor.opacity(0.12) : nil)
				.swipeActions(edge: .leading) {
					Button("Update", systemImage: "square.and.arrow.down") {
						Recording(.into(cue), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues).store(context: context)
					}
					.tint(.indigo)
					.disabled(console.active.isEmpty)
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
					
					Button("Update with Changes", systemImage: "square.and.arrow.down") {
						Recording(.into(cue), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues).store(context: context)
					}
					.disabled(console.active.isEmpty)
					
					Button("Store into Cue", systemImage: "square.and.arrow.down.on.square") {
						recording = Recording(.into(cue), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues)
					}
					
					Divider()
					
					Button("Delete Cue", systemImage: "trash", role: .destructive) {
						context.delete(cue)
					}
				}
			}
		}
		.overlay {
			if held.isEmpty {
				ContentUnavailableView {
					Label("No Cues Yet", systemImage: "list.number")
				} description: {
					Text("Set the rig for the first moment, then store it as a cue. Every cue after that keeps only what changed.")
				} actions: {
					Button("Store Cue", systemImage: "plus") {
						recording = Recording(.cue(look), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues)
					}
					.font(.headline)
					.buttonStyle(.glassProminent)
					.controlSize(.large)
				}
			}
		}
		.safeAreaBar(edge: .bottom) {
			if !held.isEmpty {
				PlaybackDeck(look: look)
			}
		}
		.navigationTitle(look.name)
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				Menu("Scene", systemImage: "ellipsis") {
					Toggle("Loop", systemImage: "repeat", isOn: $look.loops)
					
					Button("Rename", systemImage: "pencil") {
						renamed = look.name
						isRenaming = true
					}
					
					Button("Delete Scene", systemImage: "trash", role: .destructive) {
						isDeleting = true
					}
				}
			}
			
			ToolbarSpacer(.fixed, placement: .topBarTrailing)
			
			ToolbarItem(placement: .topBarTrailing) {
				Button("Store Cue", systemImage: "plus") {
					recording = Recording(.cue(look), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues)
				}
			}
		}
		.sheet(item: $recording) { recording in
			StoreView(recording: recording)
		}
		.sheet(item: $editing) { cue in
			CueEditor(cue: cue)
		}
		.alert("Rename Scene", isPresented: $isRenaming) {
			TextField("Name", text: $renamed)
				.autocorrectionDisabled()
			
			Button("Cancel", role: .cancel) {}
			
			Button("Rename") {
				look.name = renamed.trimmingCharacters(in: .whitespaces)
			}
			.disabled(renamed.trimmingCharacters(in: .whitespaces).isEmpty)
		}
		.confirmationDialog("Delete \(look.name)?", isPresented: $isDeleting, titleVisibility: .visible) {
			Button("Delete Scene", role: .destructive) {
				look.remove(with: cues, context: context)
				dismiss()
			}
		} message: {
			Text("Its cues go with it. The lights stay as they are.")
		}
		.onChange(of: looks.contains { $0.identifier == look.identifier }) {
			dismiss()
		}
	}
}

private struct CueRow: View {
	let cue: Cue
	let spots: [CueList.Spot]
	let isCurrent: Bool
	let isNext: Bool
	
	var body: some View {
		HStack(spacing: 12) {
			Text(cue.numberText)
				.font(.title3.weight(.semibold))
				.monospacedDigit()
				.lineLimit(1)
				.minimumScaleFactor(0.6)
				.frame(width: 52, height: 44)
				.foregroundStyle(isCurrent ? Color.white : Color.primary)
				.background(isCurrent ? Color.accentColor : Color(.tertiarySystemFill), in: .rect(cornerRadius: 12, style: .continuous))
			
			VStack(alignment: .leading, spacing: 6) {
				HStack(spacing: 6) {
					Text(cue.title)
						.font(.headline)
						.lineLimit(1)
					
					if isNext {
						Text("Next")
							.font(.caption2.weight(.bold))
							.foregroundStyle(.tint)
							.padding(.horizontal, 6)
							.padding(.vertical, 2)
							.background(.tint.opacity(0.15), in: .capsule)
					}
				}
				
				SpotStrip(spots: spots, size: 12, limit: 14)
				
				if isCurrent {
					CueProgress(cue: cue.entry)
				}
			}
			
			Spacer(minLength: 4)
			
			VStack(alignment: .trailing, spacing: 4) {
				Label(Cue.seconds(cue.fade, zero: "Snap"), systemImage: "arrow.up.right")
				
				if cue.delay > 0 {
					Label(Cue.seconds(cue.delay), systemImage: "hourglass")
				}
				
				if cue.trigger != .go {
					Label(cue.trigger == .wait ? Cue.seconds(cue.wait) : cue.trigger.name, systemImage: cue.trigger.symbol)
						.foregroundStyle(.tint)
				}
			}
			.font(.caption.monospacedDigit())
			.foregroundStyle(.secondary)
			.labelStyle(.titleAndIcon)
		}
		.padding(.vertical, 4)
		.contentShape(.rect)
		.accessibilityElement(children: .combine)
		.accessibilityAddTraits(isCurrent ? .isSelected : [])
	}
}
