import SwiftUI

@Observable @MainActor
final class Arrangement {
	var frames: [String: CGRect] = [:]
	var width: CGFloat = 0
	var minimum: CGFloat = 168
	
	let spacing: CGFloat = 12
	
	var columns: Int {
		TileLayout.columns(in: width, minimum: minimum, spacing: spacing)
	}
	
	private var column: CGFloat {
		(width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
	}
	
	func row(among looks: [Look]) -> CGFloat? {
		for look in looks {
			guard let frame = frames[look.identifier] else { continue }
			return (frame.height - spacing * CGFloat(look.size.rows - 1)) / CGFloat(look.size.rows)
		}
		
		return nil
	}
	
	func frame(of size: TileSize, among looks: [Look]) -> CGSize? {
		guard width > 0, let row = row(among: looks) else { return nil }
		let across = min(size.columns, columns)
		return CGSize(width: column * CGFloat(across) + spacing * CGFloat(across - 1), height: row * CGFloat(size.rows) + spacing * CGFloat(size.rows - 1))
	}
	
	func resize(_ look: Look, to size: TileSize, among looks: [Look]) {
		var board = Board(columns: columns, looks: looks)
		board.resize(look.identifier, to: size)
		
		withAnimation(.snappy(duration: 0.3)) {
			board.write(to: looks)
		}
	}
}
