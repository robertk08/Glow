import SwiftData
import SwiftUI

struct GroupView: View {
	@Environment(Console.self) private var console
	@Environment(FixtureLibrary.self) private var library
	@Environment(\.modelContext) private var context
	@Environment(\.dismiss) private var dismiss
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	
	@Bindable var group: FixtureGroup
	
	@State private var hue: Double = 0
	@State private var saturation: Double = 1
	@State private var isChoosingMembers = false
	
	private var control: GroupControl {
		GroupControl(controls: group.members.compactMap { FixtureControl(fixture: $0, library: library, console: console) })
	}
	
	private let columns = [GridItem(.adaptive(minimum: 44), spacing: 12)]
	
	var body: some View {
		Form {
			if group.members.isEmpty {
				Section {
					Button("Choose Lights", systemImage: "plus") {
						Haptic.feedback(.rigid)
						isChoosingMembers = true
					}
				}
			} else {
				if control.dims {
					Section("Brightness") {
						Slider(value: control.brightnessBinding, in: 0...1) {
							Text("Brightness")
						} minimumValueLabel: {
							Image(systemName: "sun.min")
						} maximumValueLabel: {
							Image(systemName: "sun.max")
						}
					}
				}
				
				if control.mixesColor {
					Section("Colour") {
						LazyVGrid(columns: columns, spacing: 12) {
							ForEach(ColorPreset.all(for: ChannelRole.emitters.sorted { $0.rawValue < $1.rawValue })) { preset in
								Button {
									Haptic.feedback(.selection)
									control.apply(preset)
								} label: {
									Circle()
										.fill(preset.swatch(with: [.red, .green, .blue]).color)
										.frame(height: 44)
										.overlay { Circle().strokeBorder(.separator) }
								}
								.buttonStyle(.plain)
							}
						}
						.padding(.vertical, 4)
						
						Slider(value: $hue, in: 0...1) { Text("Hue") }
							.onChange(of: hue) { control.apply(hue: hue, saturation: saturation) }
						
						Slider(value: $saturation, in: 0...1) { Text("Saturation") }
							.onChange(of: saturation) { control.apply(hue: hue, saturation: saturation) }
					}
				}
				
				if control.movesHead {
					Section("Position") {
						PositionPad(pan: Binding { control.controls.first?.fraction(.pan) ?? 0.5 } set: { control.setFraction($0, for: .pan) }, tilt: Binding { control.controls.first?.fraction(.tilt) ?? 0.5 } set: { control.setFraction($0, for: .tilt) })
						.listRowInsets(EdgeInsets())
					}
				}
			}
			
			Section {
				ForEach(group.members) { fixture in
					NavigationLink {
						FixtureView(fixture: fixture)
					} label: {
						LightRow(fixture: fixture)
					}
				}
				.onDelete { offsets in
					for index in offsets {
						group.members[index].group = nil
					}
				}
				
				Button("Choose Lights", systemImage: "plus") {
					Haptic.feedback(.rigid)
					isChoosingMembers = true
				}
			} header: {
				Text("Lights")
			}
			
			Section {
				Button("Reset") {
					Haptic.feedback(.rigid)
					control.home()
				}
				
				Button("Delete Group", role: .destructive) {
					context.delete(group)
					dismiss()
				}
			}
		}
		.navigationTitle(group.name)
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			NavigationLink {
				GroupEditView(group: group)
			} label: {
				Image(systemName: "slider.horizontal.3")
			}
		}
		.sheet(isPresented: $isChoosingMembers) {
			MemberPicker(group: group, fixtures: fixtures)
		}
	}

}

struct GroupEditView: View {
	@Bindable var group: FixtureGroup
	
	private let columns = [GridItem(.adaptive(minimum: 44), spacing: 12)]
	
	var body: some View {
		Form {
			Section {
				TextField("Name", text: $group.name)
			}
			
			Section("Icon") {
				LazyVGrid(columns: columns, spacing: 12) {
					ForEach(FixtureSymbol.all, id: \.self) { symbol in
						Button {
							Haptic.feedback(.selection)
							group.symbolOverride = symbol
						} label: {
							Image(systemName: symbol)
								.font(.title3)
								.frame(width: 44, height: 44)
								.background(group.symbol == symbol ? Color.accentColor.opacity(0.2) : .clear, in: .circle)
						}
						.buttonStyle(.plain)
					}
				}
				.padding(.vertical, 4)
				
				Picker("Colour", selection: $group.tint) {
					ForEach(FixtureTint.allCases) { tint in
						Text(tint.rawValue.capitalized).tag(tint)
					}
				}
			}
		}
		.navigationTitle(group.name)
		.navigationBarTitleDisplayMode(.inline)
	}
}

private struct MemberPicker: View {
	@Environment(\.dismiss) private var dismiss
	
	let group: FixtureGroup
	let fixtures: [Fixture]
	
	var body: some View {
		NavigationStack {
			List(fixtures) { fixture in
				Button {
					Haptic.feedback(.selection)
					fixture.group = fixture.group == group ? nil : group
				} label: {
					LabeledContent {
						if fixture.group == group {
							Image(systemName: "checkmark")
								.foregroundStyle(.tint)
						}
					} label: {
						Text(fixture.name)
					}
				}
				.buttonStyle(.plain)
			}
			.navigationTitle("Choose Lights")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				Button(role: .close) { dismiss() }
			}
		}
	}
}
