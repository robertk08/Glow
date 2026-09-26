import SwiftUI

struct WaitingView: View {
	@Environment(Console.self) private var console
	@Environment(ShowLibrary.self) private var shows
	
	@State private var password = ""
	@FocusState private var isTyping: Bool
	
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
				.padding(.bottom, 2)
				
				Group {
					FeatureRow(systemImage: "rectangle.stack", title: "Shows Live on the Controller", description: "The patch, the groups and the scenes are kept on the controller, so this device holds nothing of its own.")
					
					FeatureRow(systemImage: "arrow.triangle.2.circlepath", title: "Every Device in Step", description: "Phones and iPads on one controller see the same rig, and a scene saved on any of them appears on the rest.")
					
					FeatureRow(systemImage: "bolt", title: "Straight Down the Line", description: "What you change reaches the lights over DMX as you touch it, with no round trip to wait for.")
				}
				.opacity(isTyping ? 0 : 1)
			}
			.frame(maxWidth: 700)
			.animation(.smooth(duration: 0.35), value: isTyping)
			.toolbar(.hidden, for: .navigationBar)
			.scrollDismissesKeyboard(.interactively)
			.safeAreaBar(edge: .bottom) {
				VStack(spacing: 10) {
					if shows.standby.showsLink {
						Text(console.link.summary(latency: console.latency))
							.font(.footnote)
							.foregroundStyle(.secondary)
							.transition(.opacity)
					}
					
					if shows.standby == .locked, let lock = console.lock {
						VStack(spacing: 8) {
							if let until = console.lockedUntil {
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
								.focused($isTyping)
								.onSubmit {
									console.unlock(password: password)
								}
								.padding()
								.glassEffect()
							
							Button("Unlock") {
								console.unlock(password: password)
							}
							.buttonStyle(.glassProminent)
							.font(.headline)
							.controlSize(.large)
							.buttonSizing(.flexible)
							.disabled(password.isEmpty || console.isUnlocking || console.lockedUntil != nil)
						}
						.padding(.top)
						.transition(.opacity)
					}
					
					if shows.standby.offersSetup {
						VStack(spacing: 8) {
							NavigationLink("Set Up Controller") {
								NodeView()
							}
							.buttonStyle(.glassProminent)
							
							Button("Explore a Demo") {
								shows.startDemo()
							}
							.buttonStyle(.glass)
						}
						.font(.headline)
						.controlSize(.large)
						.buttonSizing(.flexible)
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

private struct FeatureRow: View {
	let systemImage: String
	let title: LocalizedStringKey
	let description: LocalizedStringKey
	
	var body: some View {
		HStack(spacing: 16) {
			Image(systemName: systemImage)
				.resizable()
				.scaledToFit()
				.frame(width: 44, height: 44)
				.foregroundStyle(Color.accentColor)
			
			VStack(alignment: .leading, spacing: 6) {
				Text(title)
					.font(.headline)
				
				Text(description)
					.font(.subheadline)
					.foregroundStyle(.secondary)
			}
			.minimumScaleFactor(0.8)
			
			Spacer()
		}
		.padding([.top, .leading])
	}
}
