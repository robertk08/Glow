import SwiftUI

/// What Glow says to someone who has never stood behind a lighting desk.
///
/// Two screens. The first explains three words the rest of the app uses without
/// apology — node, fixture, address — and the second offers the one thing worth
/// doing first. Both are skippable in a single tap, because the fastest way to
/// make an introduction unwelcome is to make it compulsory.
///
/// No marketing. Nobody opens a DMX console to be told it is powerful.
struct OnboardingView: View {
    /// Bump when the introduction changes enough to be worth showing again to
    /// people who have already seen it. Stored as a number rather than a flag
    /// so that is possible at all.
    static let currentVersion = 1

    /// Where ``OnboardingGate`` records what has been seen. Public so the flag
    /// has exactly one name in the project.
    static let seenVersionKey = "onboarding.seenVersion"

    @Environment(\.dismiss) private var dismiss
    @State private var page = Page.concepts
    @State private var isSettingUp = false

    private enum Page { case concepts, setUp }

    var body: some View {
        NavigationStack {
            Group {
                switch page {
                case .concepts: conceptsPage
                case .setUp: setUpPage
                }
            }
            .animation(.default, value: page)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { finish() }
                }
            }
        }
        .sheet(isPresented: $isSettingUp, onDismiss: finish) {
            NodeSetupView(mode: .newNode)
        }
    }

    // MARK: - Page 1

    private var conceptsPage: some View {
        OnboardingLayout(
            title: "Welcome to Glow",
            message: "Three words this app uses a lot, before it starts using them."
        ) {
            VStack(alignment: .leading, spacing: 24) {
                ConceptRow(
                    symbol: "wifi.router",
                    title: "The node",
                    detail: "The small box you plugged in. It sits on your Wi-Fi and turns what you do here into DMX — the signal stage lights have understood for forty years. Glow is the desk; the node is the cable."
                )
                ConceptRow(
                    symbol: "light.beacon.max",
                    title: "A fixture",
                    detail: "One light. Glow needs to know which model it is, because a light with a moving head and a colour mixer takes its instructions in a completely different order from a plain dimmer."
                )
                ConceptRow(
                    symbol: "list.number",
                    title: "An address",
                    detail: "Every light on the cable has a number, set on the light itself — usually a little display reading something like d001. It is how a light knows which part of the signal is meant for it. Two lights sharing an address do exactly the same thing."
                )
            }
        } actions: {
            Button("Continue") { page = .setUp }
                .buttonStyle(.glassProminent)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Page 2

    private var setUpPage: some View {
        OnboardingLayout(
            title: "Get the node on your Wi-Fi",
            message: "Everything the node needs is entered here — including which network to join. There is no app to install on a computer and no file to edit."
        ) {
            VStack(alignment: .leading, spacing: 24) {
                ConceptRow(
                    symbol: "powerplug",
                    title: "First",
                    detail: "Plug the node in and connect its DMX cable to your light."
                )
                ConceptRow(
                    symbol: "wifi",
                    title: "Then",
                    detail: "Setup takes about a minute. Glow will ask you to join the node's own Wi-Fi network once, and will tell you when to come back."
                )
                ConceptRow(
                    symbol: "checklist",
                    title: "After that",
                    detail: "Add your light in Patch with the address shown on its display, and bring it up on Stage."
                )
            }
        } actions: {
            Button("Set up the node") { isSettingUp = true }
                .buttonStyle(.glassProminent)
                .frame(maxWidth: .infinity)
            Button("Not now") { finish() }
                .frame(maxWidth: .infinity)
        }
    }

    private func finish() {
        UserDefaults.standard.set(Self.currentVersion, forKey: Self.seenVersionKey)
        dismiss()
    }
}

// MARK: - Presentation

/// Shows the introduction once, the first time Glow opens.
///
/// A modifier rather than a view so the decision — and the flag that records it
/// — live in one place instead of being spread between here and whoever
/// presents it. ``RootView`` writes `.firstRunOnboarding()` and needs to know
/// nothing else.
private struct OnboardingGate: ViewModifier {
    @AppStorage(OnboardingView.seenVersionKey) private var seenVersion = 0
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isPresented) {
                OnboardingView()
            }
            // Decided once, on appearance, rather than derived from the flag in
            // the body: writing the flag while the cover is on screen would
            // otherwise dismiss it out from under the closing animation.
            .onAppear { isPresented = seenVersion < OnboardingView.currentVersion }
    }
}

extension View {
    /// Presents the first-run introduction over this view, once ever.
    func firstRunOnboarding() -> some View {
        modifier(OnboardingGate())
    }
}

// MARK: - Pieces

private struct OnboardingLayout<Content: View, Actions: View>: View {
    let title: String
    let message: String
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.largeTitle.weight(.bold))
                    Text(message)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 12)

                content
            }
            .padding()
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) { actions }
                .padding()
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .background(.bar)
        }
    }
}

private struct ConceptRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        // A row rather than a slide: at the accessibility text sizes three
        // paragraphs need to scroll, and a paged carousel is the one layout
        // that cannot.
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 40, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
