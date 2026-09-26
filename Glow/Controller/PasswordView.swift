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
					if let message = console.passwordOutcome?.message {
						Text(message)
							.foregroundStyle(.red)
					} else {
						Text("Every other phone and iPad is disconnected until it enters the new password.")
					}
				}
				
				if hasPassword {
					Section {
						Button("Remove Password", role: .destructive) {
							console.protect(current: current, new: "")
						}
						.disabled(current.isEmpty || console.passwordOutcome == .saving)
					} footer: {
						Text("Anyone on this network with Glow can then control the lights.")
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
						console.protect(current: current, new: new)
					}
					.disabled(new.isEmpty || new != confirmation || (hasPassword && current.isEmpty) || console.passwordOutcome == .saving)
				}
			}
			.onChange(of: console.passwordOutcome) {
				if console.passwordOutcome == .saved { dismiss() }
			}
		}
	}
}
