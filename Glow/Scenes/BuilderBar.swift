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
	@State private var renaming: Cue?
	@State private var label = ""
	@State private var isRenaming = false
	@State private var renamed = ""
	
	var body: some View {
		if let look = looks.first(where: { $0.identifier == console.selection.building }) {
			let list = CueList(look, cues: cues, fixtures: fixtures)
			let held = look.cues(among: cues)
			let index = list.index(of: console.playback.cue(of: look.identifier))
			let current = index.map { held[$0] }
			let next = Recording(.cue(look, after: current), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues)
			let tint = look.tint.color ?? .accentColor
			
			VStack(alignment: .leading, spacing: 14) {
				HStack(spacing: 12) {
					Image(systemName: look.symbol)
						.font(.body.weight(.semibold))
						.foregroundStyle(.white)
						.frame(width: 36, height: 36)
						.background(tint, in: .circle)
					
					VStack(alignment: .leading, spacing: 1) {
						Button {
							renamed = look.name
							isRenaming = true
						} label: {
							HStack(spacing: 4) {
								Text(look.name)
									.font(.headline)
									.lineLimit(1)
								
								Image(systemName: "pencil")
									.font(.caption)
									.foregroundStyle(.secondary)
							}
							.contentShape(.rect)
						}
						.buttonStyle(.plain)
						.accessibilityHint("Renames the scene.")
						
						Text(next.hint)
							.font(.caption)
							.foregroundStyle(.secondary)
							.lineLimit(1)
							.contentTransition(.numericText())
					}
					
					Spacer(minLength: 0)
					
					Group {
						if held.isEmpty {
							Button(role: .close) {
								look.remove(with: cues, context: context)
								console.selection.building = nil
							}
							.buttonStyle(.glass)
						} else {
							Button(role: .confirm) {
								console.selection.building = nil
							}
							.buttonStyle(.glassProminent)
							.tint(tint)
						}
					}
					.labelStyle(.iconOnly)
					.buttonBorderShape(.circle)
					.controlSize(.large)
				}
				
				HStack(spacing: held.isEmpty ? 0 : 10) {
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
										.frame(minWidth: 40, minHeight: 40)
										.background(position == index ? tint.opacity(0.3) : Color(.tertiarySystemFill), in: .capsule)
										.contentShape(.capsule)
									}
									.buttonStyle(.plain)
									.id(cue.identifier)
									.accessibilityLabel("Cue \(position + 1), \(cue.title(at: position))")
									.accessibilityAddTraits(position == index ? .isSelected : [])
									.contextMenu {
										Button("Rename", systemImage: "pencil") {
											label = cue.label
											renaming = cue
										}
										
										Button("Timing and Lights", systemImage: "slider.horizontal.3") {
											editing = cue
										}
										
										Button("Add Cue After", systemImage: "text.insert") {
											recording = Recording(.cue(look, after: cue), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues)
										}
										
										Button("Store into Cue", systemImage: "square.and.arrow.down") {
											recording = Recording(.into(cue), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues)
										}
										
										Button("Delete Cue", systemImage: "trash", role: .destructive) {
											console.delete(cue, from: list, context: context)
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
					.frame(maxWidth: held.isEmpty ? 0 : .infinity, alignment: .leading)
					
					Menu {
						Button("Choose Lights and Aspects", systemImage: "slider.horizontal.3") {
							recording = next
						}
					} label: {
						Label(held.isEmpty ? "Store Cue 1" : "Cue \(next.number)", systemImage: "plus")
							.frame(maxWidth: held.isEmpty ? .infinity : nil, minHeight: 44)
					} primaryAction: {
						next.store(context: context)
					}
					.buttonStyle(.glassProminent)
					.tint(tint)
					.accessibilityLabel("Store Cue \(next.number)")
					.accessibilityHint("Touch and hold to choose the lights, aspects, name and fade.")
				}
				.font(.subheadline.weight(.semibold))
				.lineLimit(1)
			}
			.padding(16)
			.glassEffect(.regular, in: .rect(cornerRadius: 30, style: .continuous))
			.frame(maxWidth: 560)
			.padding(.horizontal, 16)
			.padding(.bottom, 8)
			.sensoryFeedback(.success, trigger: held.count)
			.sheet(item: $recording) { recording in
				StoreView(recording: recording)
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
