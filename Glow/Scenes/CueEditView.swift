import SwiftData
import SwiftUI

struct CueEditView: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.dismiss) private var dismiss
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	@Query(sort: \Cue.sortIndex) private var cues: [Cue]
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	@Bindable var cue: Cue
	
	let position: Int
	
	@State private var recording: Recording?
	
	var body: some View {
		let levels = cue.levels
		
		NavigationStack {
			Form {
				Section {
					TextField("Name or short description", text: $cue.label, axis: .vertical)
						.lineLimit(1...3)
				}
				
				Section {
					Stepper(value: $cue.fade, in: 0...600, step: 0.5) {
						LabeledContent("Fade", value: Cue.seconds(cue.fade))
							.monospacedDigit()
					}
				}
				
				Section {
					ForEach(fixtures.filter { levels.lights[$0.identifier] != nil }) { fixture in
						LabeledContent {
							Text(levels.features(of: fixture.identifier, type: library.type(fixture.typeID)).map(\.name).formatted(.list(type: .and)))
						} label: {
							Label(fixture.name, systemImage: fixture.symbol(library.type(fixture.typeID)))
						}
						.swipeActions {
							Button("Remove", systemImage: "minus.circle", role: .destructive) {
								cue.levels = levels.removing(fixture.identifier)
							}
						}
					}
					
					Button("Store the Lights into This Cue", systemImage: "square.and.arrow.down") {
						recording = Recording(.into(cue), console: console, fixtures: fixtures, library: library, looks: looks, cues: cues)
					}
				} header: {
					Text("Lights")
				} footer: {
					Text("Swipe a light to take it out of this cue. It then keeps what the cues before gave it.")
				}
			}
			.navigationTitle("Cue \(position + 1)")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button("Done") {
						dismiss()
					}
				}
			}
			.sheet(item: $recording) { recording in
				StoreView(recording: recording)
			}
		}
	}
}
