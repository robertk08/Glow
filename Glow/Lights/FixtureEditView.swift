import SwiftData
import SwiftUI

struct FixtureEditView: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.modelContext) private var context
	@Environment(\.dismiss) private var dismiss
	@Query(sort: \FixtureGroup.sortIndex) private var groups: [FixtureGroup]
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	@Bindable var fixture: Fixture
	
	@State private var named = ""
	@State private var isRemoving = false
	
	private var type: FixtureType? { library.type(fixture.typeID) }
	private var span: ClosedRange<Int> { fixture.range(type) }
	private var fits: Bool { span.upperBound <= Universe.channelCount }
	private var sharing: [Fixture] { Fixture.overlapping(fixture, among: fixtures, library: library) }
	
	private var address: Binding<Int> {
		Binding { fixture.address } set: { value in
			console.repatch(fixture, library: library) { $0.start = DMXAddress(clamping: value) }
		}
	}
	
	private var typeID: Binding<String> {
		Binding { fixture.typeID } set: { value in
			console.repatch(fixture, library: library) { $0.typeID = value }
		}
	}
	
	var body: some View {
		NavigationStack {
			Form {
				Section {
					TextField("Name", text: $fixture.name)
						.autocorrectionDisabled()
				}
				
				Section {
					Picker("Fixture", selection: typeID) {
						if type == nil {
							Text("Not Set").tag(fixture.typeID)
						}
						
						ForEach(library.types) { option in
							Text(option.mode.isEmpty ? option.name : "\(option.name), \(option.mode)").tag(option.id)
						}
					}
					
					Stepper(value: address, in: DMXAddress.range) {
						LabeledContent("Address") {
							TextField("Address", value: address, format: .number)
								.keyboardType(.numberPad)
								.multilineTextAlignment(.trailing)
								.monospacedDigit()
						}
					}
					
					if let type {
						LabeledContent("Channels", value: "\(span.lowerBound)–\(span.upperBound)")
							.monospacedDigit()
						
						NavigationLink("Edit Fixture") {
							FixtureTypeView(type: type)
						}
					}
				} header: {
					Text("Patch")
				} footer: {
					VStack(alignment: .leading, spacing: 6) {
						if type == nil {
							Label("The fixture this light was patched from is gone. Point it at another one and it keeps its name, address and group.", systemImage: "exclamationmark.triangle")
						}
						
						if !fits {
							Label("It runs past channel 512.", systemImage: "exclamationmark.triangle")
						}
						
						if !sharing.isEmpty {
							Label("Shares channels with \(sharing.map(\.name).formatted(.list(type: .and))).", systemImage: "exclamationmark.triangle")
						}
					}
					.foregroundStyle(.orange)
				}
				
				if type?.movesHead == true {
					Section("Orientation") {
						Toggle("Invert Pan", isOn: $fixture.invertsPan)
						Toggle("Invert Tilt", isOn: $fixture.invertsTilt)
					}
				}
				
				if !groups.isEmpty {
					Section("Groups") {
						ForEach(groups) { group in
							Toggle(group.name, isOn: Binding { fixture.belongs(to: group) } set: { fixture.belong(to: group, $0) })
						}
					}
				}
				
				Section("Icon") {
					AppearancePicker(symbol: Binding { fixture.symbol(type) } set: { fixture.symbolOverride = $0 })
				}
				
				Section {
					Button("Remove Light", role: .destructive) {
						isRemoving = true
					}
					.confirmationDialog("Remove \(fixture.name)?", isPresented: $isRemoving, titleVisibility: .visible) {
						Button("Remove Light", role: .destructive) {
							context.delete(fixture)
							dismiss()
						}
					} message: {
						Text("Its channels go back to zero and any scene holding it forgets it.")
					}
				}
			}
			.navigationTitle("Edit Light")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button("Done") {
						fixture.name = fixture.name.trimmingCharacters(in: .whitespaces)
						dismiss()
					}
					.disabled(fixture.name.trimmingCharacters(in: .whitespaces).isEmpty)
				}
			}
			.task {
				named = fixture.name
			}
			.onDisappear {
				fixture.name = fixture.name.trimmingCharacters(in: .whitespaces)
				guard fixture.name.isEmpty else { return }
				fixture.name = named
			}
		}
	}
}
