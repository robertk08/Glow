import SwiftData
import SwiftUI

struct BuilderBar: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.modelContext) private var context
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	@Query(sort: \Cue.sortIndex) private var cues: [Cue]
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	@State private var recording: Recording?
	@State private var editing: Cue?
	@State private var isRenaming = false
	@State private var renamed = ""
	@State private var updates = 0
	
	var body: some View {
		if let look = looks.first(where: { $0.identifier == console.selection.building }) {
			let list = CueList(look, cues: cues, fixtures: fixtures, library: library)
			let held = look.cues(among: cues)
			let index = list.index(of: console.playback.cue(of: look.identifier))
			let current = index.map { held[$0] }
			let next = Recording(.cue(look, after: current), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues)
			let tint = look.tint.color ?? .accentColor
			
			VStack(alignment: .leading, spacing: 12) {
				HStack(spacing: 12) {
					Image(systemName: look.symbol)
						.font(.body.weight(.semibold))
						.foregroundStyle(.white)
						.frame(width: 36, height: 36)
						.background(tint, in: .circle)
					
					Button {
						renamed = look.name
						isRenaming = true
					} label: {
						VStack(alignment: .leading, spacing: 1) {
							HStack(spacing: 4) {
								Text(look.name)
									.font(.headline)
									.lineLimit(1)
								
								Image(systemName: "pencil")
									.font(.caption)
									.foregroundStyle(.secondary)
							}
							
							Text(next.hint)
								.font(.caption)
								.foregroundStyle(.secondary)
								.lineLimit(1)
								.contentTransition(.numericText())
						}
						.contentShape(.rect)
					}
					.buttonStyle(.plain)
					.accessibilityHint("Renames the scene.")
					
					Spacer(minLength: 0)
					
					Button(held.isEmpty ? "Cancel" : "Done") {
						if held.isEmpty {
							look.remove(with: cues, context: context)
						}
						
						console.selection.building = nil
					}
					.buttonStyle(.glass)
				}
				
				if !held.isEmpty {
					ScrollViewReader { proxy in
						ScrollView(.horizontal) {
							HStack(spacing: 6) {
								ForEach(Array(held.enumerated()), id: \.element.identifier) { position, cue in
									Button {
										console.play(list, at: position)
									} label: {
										HStack(spacing: 6) {
											Text("\(position + 1)")
												.fontWeight(.bold)
												.monospacedDigit()
											
											if !cue.label.isEmpty {
												Text(cue.label)
													.lineLimit(1)
													.frame(maxWidth: 140)
											}
										}
										.font(.subheadline)
										.padding(.horizontal, 12)
										.frame(minWidth: 36, minHeight: 34)
										.background(position == index ? tint.opacity(0.3) : Color(.tertiarySystemFill), in: .capsule)
										.contentShape(.capsule)
									}
									.buttonStyle(.plain)
									.id(cue.identifier)
									.accessibilityLabel("Cue \(position + 1), \(cue.title(at: position))")
									.accessibilityAddTraits(position == index ? .isSelected : [])
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
							}
						}
						.scrollIndicators(.hidden)
						.onChange(of: current?.identifier) {
							withAnimation {
								proxy.scrollTo(current?.identifier, anchor: .center)
							}
						}
					}
				}
				
				HStack(spacing: 10) {
					if let current, let index {
						Button {
							Recording(.into(current), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues).update(context: context)
							updates += 1
						} label: {
							Label("Update \(index + 1)", systemImage: "arrow.triangle.2.circlepath")
								.frame(minHeight: 44)
						}
						.buttonStyle(.glass)
						.disabled(console.active.isEmpty)
					}
					
					Button {
						next.store(context: context)
					} label: {
						Label("Store Cue \(next.number)", systemImage: "plus")
							.frame(maxWidth: .infinity, minHeight: 44)
					}
					.buttonStyle(.glassProminent)
					.disabled(!next.isReady)
					
					Button {
						recording = Recording(.cue(look, after: current), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues)
					} label: {
						Label("Options", systemImage: "slider.horizontal.3")
							.labelStyle(.iconOnly)
							.frame(minWidth: 28, minHeight: 44)
					}
					.buttonStyle(.glass)
				}
				.font(.subheadline.weight(.semibold))
				.lineLimit(1)
			}
			.padding(16)
			.glassEffect(.regular, in: .rect(cornerRadius: 28, style: .continuous))
			.frame(maxWidth: 640)
			.padding(.horizontal, 12)
			.padding(.bottom, 8)
			.sensoryFeedback(.success, trigger: held.count)
			.sensoryFeedback(.success, trigger: updates)
			.sheet(item: $recording) { recording in
				StoreView(recording: recording)
			}
			.sheet(item: $editing) { cue in
				CueEditView(cue: cue, position: held.firstIndex { $0.identifier == cue.identifier } ?? 0)
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
		}
	}
}
