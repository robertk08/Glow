import SwiftUI

struct WaitingView: View {
	@Environment(Console.self) private var console
	@Environment(ShowLibrary.self) private var shows
	
	@State private var password = ""
	
	var body: some View {
		NavigationStack {
			ScrollView {
				if let icon = AppIcon.image {
					Image(uiImage: icon)
						.resizable()
						.frame(width: 152, height: 152)
						.clipShape(.rect(cornerRadius: 34))
						.shadow(color: .black.opacity(0.25), radius: 5)
						.padding(.top, 20)
				}
				
				VStack(spacing: 4) {
					Text("Welcome to")
					
					Text("Glow")
						.foregroundStyle(Color.accentColor)
				}
				.font(.system(size: 42, weight: .bold))
				.padding(.top, 20)
				
				if shows.standby.offersSetup {
					VStack(spacing: 12) {
						Button("Set Up Controller", systemImage: "wifi.router") {
							console.selection.isSetupOpen = true
						}
						.buttonStyle(.glassProminent)
						
						Button("Explore a Demo", systemImage: "sparkles") {
							shows.startDemo()
						}
						.buttonStyle(.glass)
					}
					.font(.headline)
					.controlSize(.extraLarge)
					.buttonSizing(.flexible)
					.padding(.top, 40)
					.padding(.horizontal)
					.transition(.opacity)
				}
			}
			.defaultScrollAnchor(.center, for: .alignment)
			.frame(maxWidth: 500)
			.animation(.smooth(duration: 0.35), value: shows.standby)
			.toolbar(.hidden, for: .navigationBar)
			.scrollDismissesKeyboard(.interactively)
			.safeAreaBar(edge: .bottom) {
				VStack(spacing: 10) {
					if shows.standby.offersSetup {
						HStack(spacing: 8) {
							ProgressView()
							
							Text(console.link == .full ? console.link.name : "Looking for Controller")
						}
						.font(.footnote)
						.foregroundStyle(.secondary)
						.transition(.opacity)
					}
					
					if shows.standby == .locked, let lock = console.access.lock {
						VStack(spacing: 8) {
							if let until = console.access.lockedUntil {
								Text("Too many wrong tries. Try again in \(Text(timerInterval: Date.now...until, countsDown: true)).")
									.font(.footnote)
									.foregroundStyle(.secondary)
							} else {
								Text(lock.message)
									.font(.footnote)
									.foregroundStyle(lock.isWrong ? .red : .secondary)
							}
							
							SecureField("Password", text: $password)
								.textContentType(.password)
								.submitLabel(.go)
								.onSubmit {
									console.access.unlock(password: password)
								}
								.padding()
								.glassEffect()
							
							Button("Unlock") {
								console.access.unlock(password: password)
							}
							.buttonStyle(.glassProminent)
							.font(.headline)
							.controlSize(.large)
							.buttonSizing(.flexible)
							.disabled(password.isEmpty || console.access.isUnlocking || console.access.lockedUntil != nil)
						}
						.padding(.top)
						.transition(.opacity)
					}
				}
				.frame(maxWidth: 700)
				.padding([.horizontal, .bottom])
				.animation(.smooth(duration: 0.35), value: shows.standby)
			}
		}
	}
}
