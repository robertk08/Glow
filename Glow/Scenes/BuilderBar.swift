import SwiftData
import SwiftUI

struct BuilderBar: View {
	@Environment(Console.self) private var console
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	
	var body: some View {
		VStack {
			if let look = looks.first(where: { $0.identifier == console.selection.building }) {
				BuilderPanel(look: look)
					.id(look.identifier)
					.transition(.move(edge: .bottom).combined(with: .opacity))
			}
		}
		.animation(.snappy, value: console.selection.building)
	}
}

private struct BuilderPanel: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.modelContext) private var context
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	@Query(sort: \Cue.sortIndex) private var cues: [Cue]
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	@Bindable var look: Look
	
	@State private var recording: Recording?
	@State private var editing: Cue?
	@State private var isStyling = false
	@State private var isDiscarding = false
	@State private var updates = 0
	@State private var shows = 0
	@State private var named = ""
	@FocusState private var isNaming: Bool
	
	var body: some View {
		if !look.isGone {
			let held = look.cues(among: cues)
			let index = console.marked(among: held)
			let current = index.map { held[$0] }
			let next = Recording(.cue(look, after: current), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues)
			let update = current.map { Recording(.into($0), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues) }
			let isMoving = console.isMoving
			let canUpdate = !isMoving && update?.isReady == true
			let isOnStage = isMoving || update?.isOnStage ?? true
			let hasChanged = console.hasChanged(look, among: cues)
			let tint = look.tint.color ?? .accentColor
			
			VStack(alignment: .leading, spacing: 14) {
				HStack(spacing: 12) {
					Button {
						isStyling.toggle()
					} label: {
						Image(systemName: isStyling ? "chevron.down" : look.symbol)
							.font(.body.weight(.semibold))
							.foregroundStyle(.white)
							.contentTransition(.symbolEffect(.replace))
							.frame(width: 40, height: 40)
							.background(tint, in: .circle)
					}
					.buttonStyle(.plain)
					.accessibilityLabel("Icon and Colour")
					.accessibilityAddTraits(isStyling ? .isSelected : [])
					
					VStack(alignment: .leading, spacing: 1) {
						TextField("Name", text: $look.name)
							.font(.headline)
							.autocorrectionDisabled()
							.submitLabel(.done)
							.focused($isNaming)
						
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
					
					HStack(spacing: 8) {
						if hasChanged || held.isEmpty && console.selection.isNew {
							Button(role: .close) {
								if hasChanged {
									isDiscarding = true
								} else {
									console.discard(look, among: cues, fixtures: fixtures, context: context)
								}
							}
							.buttonStyle(.glass)
							.transition(.scale.combined(with: .opacity))
							.confirmationDialog("Discard", isPresented: $isDiscarding) {
								Button(console.selection.isNew ? "Delete Scene" : "Discard Changes", role: .destructive) {
									console.discard(look, among: cues, fixtures: fixtures, context: context)
								}
							}
						}
						
						if !held.isEmpty || !console.selection.isNew {
							Button(role: .confirm) {
								look.settle(name: named, among: looks)
								console.selection.building = nil
							}
							.buttonStyle(.glassProminent)
							.tint(tint)
							.transition(.scale.combined(with: .opacity))
						}
					}
					.labelStyle(.iconOnly)
					.buttonBorderShape(.circle)
					.controlSize(.large)
				}
				
				if isStyling {
					AppearancePicker(symbol: Binding { look.symbol } set: { look.symbolOverride = $0 }, tint: $look.tint)
						.transition(.opacity.combined(with: .move(edge: .bottom)))
				} else if !held.isEmpty {
					ScrollViewReader { proxy in
						ScrollView(.horizontal) {
							HStack(spacing: 6) {
								ForEach(Array(held.enumerated()), id: \.element.identifier) { position, cue in
									Button {
										if position == index {
											editing = cue
										} else {
											console.selection.marked = cue.identifier
										}
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
										.foregroundStyle(position == index ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
										.padding(.horizontal, 14)
										.frame(minWidth: 44, minHeight: 36)
										.background(position == index ? tint : Color(.tertiarySystemFill), in: .capsule)
										.contentShape(.capsule)
									}
									.buttonStyle(.plain)
									.id(cue.identifier)
									.transition(.scale.combined(with: .opacity))
									.accessibilityLabel("Cue \(position + 1)")
									.accessibilityValue(cue.label)
									.accessibilityAddTraits(position == index ? .isSelected : [])
									.accessibilityHint(position == index ? "Edits it." : "New cues go after it.")
								}
							}
						}
						.scrollIndicators(.hidden)
						.contentMargins(.horizontal, 16, for: .scrollContent)
						.padding(.horizontal, -16)
						.onAppear {
							proxy.scrollTo(current?.identifier, anchor: .center)
						}
						.onChange(of: current?.identifier) {
							Task {
								withAnimation {
									proxy.scrollTo(current?.identifier, anchor: .center)
								}
							}
						}
					}
				}
				
				HStack(spacing: 8) {
					Button("Choose Lights and Aspects", systemImage: "slider.horizontal.3") {
						recording = next
					}
					.labelStyle(.iconOnly)
					.buttonStyle(.glass)
					.buttonBorderShape(.circle)
					
					if let update, let index, !isOnStage {
						Button("Show Cue \(index + 1)", systemImage: "play.fill") {
							update.show()
							shows += 1
						}
						.labelStyle(.iconOnly)
						.buttonStyle(.glass)
						.buttonBorderShape(.circle)
						.transition(.scale.combined(with: .opacity))
					}
					
					if let update, let index, canUpdate {
						Button {
							update.store(context: context)
							updates += 1
						} label: {
							ViewThatFits(in: .horizontal) {
								Label("Update \(index + 1)", systemImage: "arrow.triangle.2.circlepath")
								
								Text("Update \(index + 1)")
							}
							.frame(maxWidth: .infinity)
						}
						.buttonStyle(.glass)
						.transition(.scale.combined(with: .opacity))
					}
					
					Button {
						next.store(context: context)
						isStyling = false
					} label: {
						Label("Cue \(next.number)", systemImage: "plus")
							.frame(maxWidth: .infinity)
					}
					.buttonStyle(.glassProminent)
					.tint(tint)
					.disabled(!next.isReady)
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
			.animation(.snappy, value: [held.count, index ?? -1])
			.animation(.snappy, value: [isStyling, canUpdate, isOnStage, hasChanged])
			.sensoryFeedback(.success, trigger: held.count)
			.sensoryFeedback(.success, trigger: updates)
			.sensoryFeedback(.impact(weight: .light), trigger: shows)
			.sensoryFeedback(.selection, trigger: index)
			.sensoryFeedback(.selection, trigger: [look.symbol, look.tint.rawValue])
			.onAppear {
				console.keep(look, among: cues, fixtures: fixtures, library: library)
				named = look.name
			}
			.onChange(of: isNaming) {
				if isNaming {
					named = look.name
				} else {
					look.settle(name: named, among: looks)
				}
			}
			.sheet(item: $recording) { recording in
				StoreView(recording: recording)
			}
			.sheet(item: $editing) { cue in
				CueEditView(cue: cue)
			}
		}
	}
}
