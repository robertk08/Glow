import SwiftData
import SwiftUI

struct PatchView: View {
	@Environment(FixtureLibrary.self) private var library
	@Environment(Console.self) private var console
	@Environment(\.modelContext) private var context
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	let mode: FixtureMode
	
	@Binding var isPresented: Bool
	
	@State private var name = ""
	@State private var count = 1
	@State private var address = 1
	@State private var hasChosenAddress = false
	
	private var width: Int { max(1, mode.channelCount) }
	private var lastAddress: Int { address + width * count - 1 }
	private var fits: Bool { lastAddress <= Universe.channelCount }
	
	var body: some View {
		Form {
			Section {
				TextField("Name", text: $name)
					.autocorrectionDisabled()
			} footer: {
				Text("Leave empty to use the fixture's own name.")
			}
			
			Section {
				Stepper(value: $count, in: 1...64) {
					LabeledContent("How many", value: "\(count)")
						.monospacedDigit()
				}
			} footer: {
				if count > 1 {
					Text("Each one gets the next free block of \(width) channels.")
				}
			}
			
			Section {
				Stepper(value: $address, in: DMXAddress.range) {
					LabeledContent("Start address", value: "\(address)")
						.monospacedDigit()
				}
				
				LabeledContent("Uses", value: count == 1 ? "\(address)–\(lastAddress)" : "\(address)–\(lastAddress), \(width) each")
					.monospacedDigit()
			} header: {
				Text("Address")
			} footer: {
				if !fits {
					Text("That runs past channel 512.")
						.foregroundStyle(.orange)
				}
			}
			
			Section {
				Button("Add to the Patch") {
					console.patch(mode, count: count, at: address, named: name, among: fixtures, context: context)
					isPresented = false
				}
				.font(.headline)
				.buttonStyle(.glassProminent)
				.controlSize(.large)
				.frame(maxWidth: .infinity)
				.disabled(!fits)
			}
			.listRowBackground(Color.clear)
		}
		.navigationTitle(mode.model)
		.navigationBarTitleDisplayMode(.inline)
		.task {
			guard !hasChosenAddress else { return }
			hasChosenAddress = true
			address = Fixture.firstFreeAddress(width: width, among: fixtures, library: library)
		}
	}
}
