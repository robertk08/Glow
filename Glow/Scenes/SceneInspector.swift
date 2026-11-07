import SwiftData
import SwiftUI

struct SceneInspector: View {
	@Environment(Console.self) private var console
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	
	var body: some View {
		let shown = console.shownScene(among: looks.map(\.identifier))
		
		if let look = looks.first(where: { $0.identifier == shown }) {
			SceneView(look: look)
				.id(look.identifier)
		} else {
			ContentUnavailableView {
				Label(looks.isEmpty ? "No Scenes Yet" : "Nothing Selected", systemImage: "theatermasks")
			} description: {
				if !looks.isEmpty {
					Text("Play a scene to follow its cues here.")
				}
			}
			.safeAreaBar(edge: .bottom) {
				MasterBar(isRaised: true)
			}
		}
	}
}
