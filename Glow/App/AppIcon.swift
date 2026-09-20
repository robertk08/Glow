import UIKit

nonisolated enum AppIcon {
	static let image: UIImage? = {
		guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any] else { return nil }
		guard let primary = icons["CFBundlePrimaryIcon"] as? [String: Any] else { return nil }
		
		var names: [String] = []
		if let files = primary["CFBundleIconFiles"] as? [String] { names = files.reversed() }
		if let name = primary["CFBundleIconName"] as? String { names.append(name) }
		
		for name in names {
			guard let found = UIImage(named: name) else { continue }
			guard found.cgImage != nil, found.size.width > 0, found.size.height > 0 else { continue }
			return found
		}
		
		return nil
	}()
}
