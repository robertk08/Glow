import SwiftUI

struct NameSheet: View {
	@Environment(\.dismiss) private var dismiss
	
	let title: LocalizedStringKey
	let prompt: LocalizedStringKey
	var hint: LocalizedStringKey?
	
	@Binding var name: String
	
	let save: (String) -> Void
	
	@FocusState private var isFocused: Bool
	
	var body: some View {
		NavigationStack {
			Form {
				Section {
					TextField(prompt, text: $name)
						.focused($isFocused)
						.autocorrectionDisabled()
						.submitLabel(.done)
				} footer: {
					if let hint {
						Text(hint)
					}
				}
			}
			.navigationTitle(title)
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button(role: .cancel) { dismiss() }
				}
				
				ToolbarItem(placement: .confirmationAction) {
					Button(role: .confirm) {
						save(name.trimmingCharacters(in: .whitespaces))
						dismiss()
					}
					.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
				}
			}
		}
		.presentationDetents([.medium])
		.task {
			isFocused = true
		}
	}
}
