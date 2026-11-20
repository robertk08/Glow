import SwiftUI

struct PasswordView: View {
	@Environment(Console.self) private var console
	@Environment(\.dismiss) private var dismiss
	
	@State private var current = ""
	@State private var new = ""
	@State private var confirmation = ""
	
	var body: some View {
		let hasPassword = console.node?.hasPassword ?? false
		
		NavigationStack {
			Form {
				if hasPassword {
					Section {
						SecureField("Current Password", text: $current)
							.textContentType(.password)
					}
				}
				
				Section {
					SecureField("New Password", text: $new)
						.textContentType(.newPassword)
					
					SecureField("Confirm Password", text: $confirmation)
						.textContentType(.newPassword)
				} footer: {
					if let message = console.access.passwordOutcome?.message {
						Text(message)
							.foregroundStyle(.red)
					}
				}
				
				if hasPassword {
					Section {
						Button("Remove Password", role: .destructive) {
							if let node = console.node { console.access.protect(current: current, new: "", on: node) }
						}
						.disabled(current.isEmpty || console.access.passwordOutcome == .saving)
					}
				}
			}
			.navigationTitle(console.node?.passwordAction ?? "")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button(role: .cancel) {
						dismiss()
					}
				}
				
				ToolbarItem(placement: .confirmationAction) {
					Button(role: .confirm) {
						if let node = console.node { console.access.protect(current: current, new: new, on: node) }
					}
					.disabled(new.isEmpty || new != confirmation || (hasPassword && current.isEmpty) || console.access.passwordOutcome == .saving)
				}
			}
			.onChange(of: console.access.passwordOutcome) {
				if console.access.passwordOutcome == .saved { dismiss() }
			}
		}
	}
}
