import SwiftData
import SwiftUI

struct CueEditView: View {
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	@Query(sort: \Cue.sortIndex) private var cues: [Cue]
	
	@State private var identifier: String
	
	init(cue: Cue) {
		_identifier = State(initialValue: cue.identifier)
	}
	
	var body: some View {
		NavigationStack {
			if let cue = cues.first(where: { $0.identifier == identifier }) {
				let held = looks.first { $0.identifier == cue.lookID }?.cues(among: cues) ?? [cue]
				
				CueForm(cue: cue, held: held, identifier: $identifier)
			}
		}
	}
}

private struct CueForm: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.dismiss) private var dismiss
	@Environment(\.modelContext) private var context
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	@Query(sort: \Cue.sortIndex) private var cues: [Cue]
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	@Bindable var cue: Cue
	
	let held: [Cue]
	
	@Binding var identifier: String
	
	@State private var recording: Recording?
	
	var body: some View {
		let levels = cue.levels
		let position = held.firstIndex { $0.identifier == cue.identifier } ?? 0
		
		Form {
			Section {
				TextField("Cue \(position + 1)", text: $cue.label, axis: .vertical)
					.lineLimit(1...3)
			}
			
			Section {
				CueTiming(fade: $cue.fade, delay: $cue.delay, follow: $cue.follow)
			}
			
			Section {
				ForEach(fixtures.filter { levels.lights[$0.identifier] != nil }) { fixture in
					let features = levels.features(of: fixture.identifier, type: library.type(fixture.typeID))
					
					LabeledContent {
						HStack(spacing: 8) {
							ForEach(features) { feature in
								Image(systemName: feature.symbol)
							}
						}
						.accessibilityElement(children: .ignore)
						.accessibilityLabel(features.map(\.name).formatted(.list(type: .and)))
					} label: {
						Label(fixture.name, systemImage: fixture.symbol(library.type(fixture.typeID)))
					}
					.swipeActions {
						Button("Remove", systemImage: "minus.circle", role: .destructive) {
							cue.levels = levels.removing(fixture.identifier)
						}
					}
				}
			} header: {
				Text("Lights")
			}
			
			Section {
				Button("Update Cue", systemImage: "arrow.triangle.2.circlepath") {
					recording = Recording(.into(cue), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues)
				}
				.disabled(!console.isTouched)
				
				Button("Delete Cue", systemImage: "trash", role: .destructive) {
					if let look = looks.first(where: { $0.identifier == cue.lookID }) {
						console.delete(cue, from: CueList(look, cues: cues, fixtures: fixtures), context: context)
					}
					
					dismiss()
				}
				.foregroundStyle(.red)
			}
		}
		.navigationTitle("Cue \(position + 1)")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItemGroup(placement: .topBarLeading) {
				Button("Previous Cue", systemImage: "chevron.up") {
					identifier = held[position - 1].identifier
				}
				.disabled(position == 0)
				
				Button("Next Cue", systemImage: "chevron.down") {
					identifier = held[position + 1].identifier
				}
				.disabled(position >= held.count - 1)
			}
			
			ToolbarItem(placement: .confirmationAction) {
				Button(role: .confirm) {
					dismiss()
				}
			}
		}
		.sheet(item: $recording) { recording in
			StoreView(recording: recording)
		}
	}
}
