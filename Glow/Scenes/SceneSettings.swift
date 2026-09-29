import SwiftData
import SwiftUI

struct SceneSettings: View {
	@Environment(Console.self) private var console
	@Environment(\.dismiss) private var dismiss
	@Environment(\.modelContext) private var context
	@Query(sort: \Cue.sortIndex) private var cues: [Cue]
	@Query(sort: \Fixture.sortIndex) private var fixtures: [Fixture]
	@ScaledMetric(relativeTo: .headline) private var tileWidth = 168
	@ScaledMetric(relativeTo: .headline) private var tileHeight = 150
	
	@Bindable var look: Look
	
	@State private var isDeleting = false
	
	var body: some View {
		NavigationStack {
			if !look.isGone {
				content
			}
		}
	}
	
	@ViewBuilder private var content: some View {
		let tint = look.tint.color ?? .accentColor
		
		Form {
			Section {
				SceneFace(look: look, list: CueList(look, cues: cues, fixtures: fixtures), showsButtons: true)
					.frame(width: look.size == .small ? tileWidth : nil, height: look.size == .large ? tileHeight * 2 + 12 : nil)
					.frame(maxWidth: .infinity)
					.allowsHitTesting(false)
					.accessibilityHidden(true)
			}
			.listRowBackground(Color.clear)
			.listRowInsets(EdgeInsets())
			
			Section {
				TextField("Name", text: $look.name)
					.autocorrectionDisabled()
			}
			
			Section {
				Picker("Size", selection: $look.size) {
					ForEach(TileSize.allCases) { size in
						Text(size.name)
							.tag(size)
					}
				}
				.pickerStyle(.segmented)
				
				Picker("Tap", selection: $look.tap) {
					ForEach(SceneAction.taps) { action in
						Label(action.name, systemImage: action.symbol)
							.tag(action)
					}
				}
			} header: {
				Text("Tile")
			}
			
			if look.size != .small {
				Section {
					ForEach(look.buttons + SceneAction.buttons.filter { !look.buttons.contains($0) }) { action in
						let isOn = look.buttons.contains(action)
						
						Button {
							look.shows(action, !isOn)
						} label: {
							HStack(spacing: 16) {
								Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
									.font(.title3)
									.foregroundStyle(isOn ? AnyShapeStyle(tint) : AnyShapeStyle(.tertiary))
								
								Label(action.name, systemImage: action.symbol)
									.foregroundStyle(isOn ? .primary : .secondary)
								
								Spacer(minLength: 0)
							}
							.contentShape(.rect)
						}
						.buttonStyle(.plain)
						.accessibilityAddTraits(isOn ? .isSelected : [])
						.moveDisabled(!isOn)
					}
					.onMove { from, to in
						var order = look.buttons + SceneAction.buttons.filter { !look.buttons.contains($0) }
						let chosen = Set(look.buttons)
						order.move(fromOffsets: from, toOffset: to)
						look.buttons = order.filter(chosen.contains)
					}
				} header: {
					Text("Buttons")
				}
			}
			
			Section {
				AppearancePicker(symbol: Binding { look.symbol } set: { look.symbolOverride = $0 }, tint: $look.tint)
			} header: {
				Text("Icon and Colour")
			}
			
			Section {
				Button("Delete Scene", systemImage: "trash", role: .destructive) {
					isDeleting = true
				}
			}
		}
		.environment(\.editMode, .constant(.active))
		.animation(.snappy, value: look.buttons)
		.animation(.snappy, value: look.size)
		.navigationTitle(look.name)
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .confirmationAction) {
				Button(role: .confirm) {
					dismiss()
				}
			}
		}
		.confirmationDialog("Delete \(look.name)?", isPresented: $isDeleting, titleVisibility: .visible) {
			Button("Delete Scene", role: .destructive) {
				console.remove(look, with: cues, context: context)
				dismiss()
			}
		}
	}
}
