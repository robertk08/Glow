import SwiftData
import SwiftUI

struct SceneInspector: View {
	@Environment(Console.self) private var console
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	
	var body: some View {
		if let look = looks.first(where: { $0.identifier == console.selection.scene }) {
			SceneView(look: look)
				.id(look.identifier)
		} else {
			ContentUnavailableView {
				Label("No Scene Chosen", systemImage: "theatermasks")
			} description: {
				Text("Tap a scene to run it and see its cues here.")
			}
		}
	}
}
