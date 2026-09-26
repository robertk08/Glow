import SwiftData
import SwiftUI

struct CueEditor: View {
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.dismiss) private var dismiss
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	@Bindable var cue: Cue
	
	@State private var number: String
	
	init(cue: Cue) {
		self.cue = cue
		_number = State(initialValue: cue.numberText)
	}
	
	var body: some View {
		let levels = cue.levels
		let held = fixtures.filter { levels.lights[$0.identifier] != nil }
		let gone = levels.lights.keys.filter { identifier in !fixtures.contains { $0.identifier == identifier } }.sorted()
		
		NavigationStack {
			Form {
				Section {
					LabeledContent("Number") {
						TextField("Number", text: $number)
							.keyboardType(.decimalPad)
							.multilineTextAlignment(.trailing)
							.monospacedDigit()
					}
					
					TextField("Name", text: $cue.name)
				}
				
				Section("Timing") {
					SecondsPicker(title: "Fade", seconds: $cue.fade, zero: "Snap")
					SecondsPicker(title: "Delay", seconds: $cue.delay)
				}
				
				Section {
					Picker("Starts", selection: $cue.trigger) {
						ForEach(Trigger.allCases) { trigger in
							Label(trigger.name, systemImage: trigger.symbol)
								.tag(trigger)
						}
					}
					
					if cue.trigger == .wait {
						SecondsPicker(title: "After", seconds: $cue.wait)
					}
				} footer: {
					switch cue.trigger {
					case .go: Text("Waits for Go.")
					case .follow: Text("Starts by itself once the cue before it has finished fading.")
					case .wait: Text("Starts by itself this long after the cue before it began.")
					}
				}
				
				Section {
					ForEach(held) { fixture in
						LabeledContent {
							Text(levels.features(of: fixture.identifier, type: library.type(fixture.typeID)).map(\.name).formatted(.list(type: .and)))
								.font(.caption)
								.foregroundStyle(.secondary)
						} label: {
							Label(fixture.name, systemImage: fixture.symbol(library.type(fixture.typeID)))
						}
						.swipeActions {
							Button("Remove", systemImage: "minus.circle", role: .destructive) {
								cue.levels = levels.removing(fixture.identifier)
							}
						}
					}
					
					ForEach(gone, id: \.self) { identifier in
						Label("A Removed Light", systemImage: "questionmark.circle")
							.foregroundStyle(.secondary)
							.swipeActions {
								Button("Remove", systemImage: "minus.circle", role: .destructive) {
									cue.levels = levels.removing(identifier)
								}
							}
					}
				} header: {
					Text("Lights")
				} footer: {
					Text(held.isEmpty ? "This cue holds no lights, so it only moves the list on." : "Swipe a light to take it out of this cue. It then keeps whatever the cues before gave it.")
				}
			}
			.navigationTitle("Cue \(cue.numberText)")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button("Done") {
						dismiss()
					}
				}
			}
			.onDisappear {
				cue.number = Cue.number(number) ?? cue.number
			}
		}
	}
}
