import Foundation

enum DimmerKind: Equatable {
	case linear
	case band(from: UInt8, to: UInt8, open: UInt8?)
}
