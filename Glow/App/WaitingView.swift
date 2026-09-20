import SwiftUI

struct WaitingView: View {
	@Environment(Console.self) private var console
	@Environment(ShowLibrary.self) private var shows
	
	var body: some View {
		NavigationStack {
			ContentUnavailableView {
				Label("Waiting for the Controller", systemImage: console.link.symbol)
					.foregroundStyle(console.link.tint)
			} description: {
				if let node = console.node {
					Text("\(node.name) is answering on firmware \(node.firmware), but it has not handed over a show yet.")
				} else {
					Text(console.link.explanation)
				}
			} actions: {
				NavigationLink("Set Up Controller") {
					NodeView()
				}
				.buttonStyle(.borderedProminent)
				
				Button("Explore a Demo") {
					shows.startDemo()
				}
			}
			.navigationTitle(console.link.name)
			.navigationBarTitleDisplayMode(.inline)
		}
	}
}
