import SwiftUI

struct SceneSettings: View {
	@Environment(\.dismiss) private var dismiss
	
	@Bindable var look: Look
	
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
						Text(action.name)
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
	}
}
