import SwiftData
import SwiftUI

struct AddLightView: View {
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.dismiss) private var dismiss
	
	@Binding var isPresented: Bool
	
	@State private var query = ""
	@State private var isBuilding = false
	
	private var results: [FixtureProfile] { library.search(query) }
	
	var body: some View {
		NavigationStack {
			List {
				Section {
					Button("Build a Fixture", systemImage: "slider.horizontal.3") {
						isBuilding = true
					}
				}
				
				Section {
					ForEach(results) { profile in
						NavigationLink {
							PatchFixtureView(profile: profile, isPresented: $isPresented)
						} label: {
							Label {
								VStack(alignment: .leading) {
									Text(profile.model)
									Text(profile.mode)
										.font(.caption)
										.foregroundStyle(.secondary)
								}
							} icon: {
								Image(systemName: profile.symbol)
							}
						}
					}
				}
			}
			.navigationTitle("Add Light")
			.navigationBarTitleDisplayMode(.inline)
			.searchable(text: $query)
			.overlay {
				if results.isEmpty {
					ContentUnavailableView {
						Label("Nothing Found", systemImage: "magnifyingglass")
					} description: {
						Text("Try a different name, or build the fixture yourself.")
					} actions: {
						Button("Build a Fixture", systemImage: "slider.horizontal.3") {
							isBuilding = true
						}
						.buttonStyle(.glassProminent)
					}
				}
			}
			.toolbar {
				Button(role: .close) { dismiss() }
			}
			.sheet(isPresented: $isBuilding) {
				CustomFixtureView()
			}
		}
	}
}

struct PatchFixtureView: View {
	@Environment(FixtureLibrary.self) private var library
	@Environment(Console.self) private var console
	@Environment(\.modelContext) private var context
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	let profile: FixtureProfile
	
	@Binding var isPresented: Bool
	
	@State private var name = ""
	@State private var count = 1
	@State private var address = 1
	@State private var hasChosenAddress = false
	
	private var width: Int { max(1, profile.channelCount) }
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
				}
			} footer: {
				if count > 1 {
					Text("Each one gets the next free block of \(width) channels.")
				}
			}
			
			Section {
				Stepper(value: $address, in: DMXAddress.range) {
					LabeledContent("Start address", value: "\(address)")
				}
				
				LabeledContent("Uses", value: count == 1 ? "\(address)–\(lastAddress)" : "\(address)–\(lastAddress), \(width) each")
			} header: {
				Text("Address")
			} footer: {
				if !fits {
					Text("That runs past channel 512.")
						.foregroundStyle(.orange)
				}
			}
			
			Section {
				Button("Add") {
					var next = address
					var index = (fixtures.map(\.sortIndex).max() ?? 0) + 1
					let base = name.trimmingCharacters(in: .whitespaces).isEmpty ? profile.model : name
					
					for number in 0..<count {
						guard let start = DMXAddress(next) else { break }
						let title = count == 1 ? Fixture.unusedName(base, among: fixtures) : "\(base) \(number + 1)"
						context.insert(Fixture(profileID: profile.id, name: title, address: start, sortIndex: index))
						FixtureControl(profile: profile, start: start, console: console).applyDefaults()
						next += width
						index += 1
					}
					
					isPresented = false
				}
				.disabled(!fits)
			}
		}
		.navigationTitle(profile.model)
		.navigationBarTitleDisplayMode(.inline)
		.task {
			guard !hasChosenAddress else { return }
			hasChosenAddress = true
			address = Fixture.firstFreeAddress(width: width, among: fixtures, library: library)
		}
	}
}
