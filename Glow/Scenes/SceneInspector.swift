import SwiftData
import SwiftUI

struct SceneInspector: View {
	@Environment(Console.self) private var console
	@Query(sort: \Look.sortIndex) private var looks: [Look]
	
	var body: some View {
		if let look = looks.first(where: { $0.identifier == console.selection.scene }) ?? looks.first(where: { $0.identifier == console.playback.playing.last?.scene }) ?? looks.first {
			SceneView(look: look)
				.id(look.identifier)
		} else {
			ContentUnavailableView {
				Label("No Scenes Yet", systemImage: "theatermasks")
			} description: {
				Text("A scene you store shows its cues here.")
			}
		}
	}
}
