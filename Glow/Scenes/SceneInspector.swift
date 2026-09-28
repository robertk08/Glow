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
				Label("No Scenes Yet", systemImage: "theatermasks")
			}
			.safeAreaBar(edge: .bottom) {
				MasterBar(isRaised: true)
			}
		}
	}
}
