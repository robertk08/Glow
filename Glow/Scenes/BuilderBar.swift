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
	
	var body: some View {
		if let look = looks.first(where: { $0.identifier == console.selection.building }) {
			@Bindable var look = look
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
						.frame(width: 40, height: 40)
						.background(tint, in: .circle)
					
					VStack(alignment: .leading, spacing: 1) {
						TextField("Name", text: $look.name)
							.font(.headline)
							.autocorrectionDisabled()
							.submitLabel(.done)
						
						HStack(spacing: 6) {
							Text(next.hint)
								.contentTransition(.numericText())
							
							if next.features.count < FeatureGroup.allCases.count {
								ForEach(FeatureGroup.allCases.filter(next.features.contains)) { feature in
									Image(systemName: feature.symbol)
										.accessibilityLabel(feature.name)
								}
							}
						}
						.font(.caption)
						.foregroundStyle(.secondary)
						.lineLimit(1)
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
				
				if !held.isEmpty {
					ScrollViewReader { proxy in
						ScrollView(.horizontal) {
							HStack(spacing: 6) {
								ForEach(Array(held.enumerated()), id: \.element.identifier) { position, cue in
									Button {
										console.play(list, at: position)
									} label: {
										HStack(spacing: 6) {
											Text(cue.number)
												.fontWeight(.bold)
												.monospacedDigit()
											
											if !cue.label.isEmpty {
												Text(cue.label)
													.lineLimit(1)
													.frame(maxWidth: 140)
											}
										}
										.font(.subheadline)
										.foregroundStyle(position == index ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
										.padding(.horizontal, 14)
										.frame(minWidth: 44, minHeight: 36)
										.background(position == index ? tint : Color(.tertiarySystemFill), in: .capsule)
										.contentShape(.capsule)
									}
									.buttonStyle(.plain)
									.id(cue.identifier)
									.transition(.scale.combined(with: .opacity))
									.accessibilityLabel(cue.title)
									.accessibilityAddTraits(position == index ? .isSelected : [])
									.contextMenu {
										Button("Edit", systemImage: "slider.horizontal.3") {
											editing = cue
										}
										
										Button("Add Cue After", systemImage: "text.insert") {
											recording = Recording(.cue(look, after: cue), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues)
										}
										
										Button("Delete Cue", systemImage: "trash", role: .destructive) {
											console.delete(cue, from: list, context: context)
										}
									}
								}
							}
							.padding(.horizontal, 2)
						}
						.scrollIndicators(.hidden)
						.scrollClipDisabled()
						.onChange(of: current?.identifier) {
							withAnimation {
								proxy.scrollTo(current?.identifier, anchor: .center)
							}
						}
					}
				}
				
				HStack(spacing: 10) {
					Button("Choose Lights and Aspects", systemImage: "slider.horizontal.3") {
						recording = next
					}
					.labelStyle(.iconOnly)
					.buttonStyle(.glass)
					.buttonBorderShape(.circle)
					
					if let current, console.canUpdate(current) {
						Button {
							Recording(.into(current), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues).store(context: context)
						} label: {
							Label("Update \(current.number)", systemImage: "arrow.triangle.2.circlepath")
								.frame(maxWidth: .infinity)
						}
						.buttonStyle(.glass)
						.transition(.scale.combined(with: .opacity))
					}
					
					Button {
						next.store(context: context)
					} label: {
						Label("Cue \(next.number)", systemImage: "plus")
							.frame(maxWidth: .infinity)
					}
					.buttonStyle(.glassProminent)
					.tint(tint)
					.accessibilityLabel("Store Cue \(next.number)")
				}
				.controlSize(.large)
				.font(.subheadline.weight(.semibold))
				.lineLimit(1)
			}
			.padding(16)
			.glassEffect(.regular, in: .rect(cornerRadius: 30, style: .continuous))
			.frame(maxWidth: 560)
			.padding(.horizontal, 16)
			.padding(.bottom, 8)
			.animation(.snappy, value: held.count)
			.animation(.snappy, value: current.map(console.canUpdate))
			.sensoryFeedback(.success, trigger: held.count)
			.sheet(item: $recording) { recording in
				StoreView(recording: recording)
			}
			.sheet(item: $editing) { cue in
				CueEditView(cue: cue)
			}
		}
	}
}
