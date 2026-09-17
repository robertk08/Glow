import SwiftData
import SwiftUI

@Model
final class Look {
	var name: String = ""
	var sortIndex: Int = 0
	var values: Data = Data()
	
	init(name: String, sortIndex: Int, values: [UInt8]) {
		self.name = name
		self.sortIndex = sortIndex
		self.values = Data(values)
	}
	
	var channels: [UInt8] { [UInt8](values) }
	
	var litCount: Int { channels.count { $0 > 0 } }
}
