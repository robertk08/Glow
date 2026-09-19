import SwiftData
import SwiftUI

@Model
final class CustomProfile {
	var identifier: String = UUID().uuidString
	var name: String = ""
	var symbol: String = "lightbulb"
	var channelList: [CustomChannel] = []
	var createdAt: Date = Date.now
	var isSubtractive: Bool = false
	var manufacturer: String = ""
	var mode: String = ""
	var panDegrees: Double?
	var tiltDegrees: Double?
	var invertsPan: Bool = false
	var invertsTilt: Bool = false
	
	init(name: String, symbol: String, channels: [CustomChannel], isSubtractive: Bool) {
		identifier = "custom-\(UUID().uuidString)"
		self.name = name
		self.symbol = symbol
		channelList = channels
		self.isSubtractive = isSubtractive
		createdAt = .now
	}
	
	convenience init(profile: FixtureProfile?) {
		self.init(name: profile?.model ?? "", symbol: profile?.symbol ?? "lightbulb", channels: [], isSubtractive: profile?.mixing == .subtractive)
		guard let profile else {
			channelList = [CustomChannel(role: .intensity)]
			return
		}
		identifier = profile.id
		manufacturer = profile.manufacturer
		mode = profile.mode
		panDegrees = profile.panDegrees
		tiltDegrees = profile.tiltDegrees
		invertsPan = profile.invertsPan
		invertsTilt = profile.invertsTilt
		for offset in 0..<profile.channelCount {
			let source = profile.channels.first { $0.offset == offset + 1 }
			var channel = CustomChannel(role: source?.role ?? .custom, name: source?.name ?? "")
			channel.defaultValue = source?.defaultValue ?? 0
			channel.isFine = source?.isFine ?? false
			channel.ranges = source?.ranges ?? []
			channelList.append(channel)
		}
	}
	
	func adopt(_ draft: CustomProfile) {
		name = draft.name
		symbol = draft.symbol
		channelList = draft.channelList
		isSubtractive = draft.isSubtractive
		manufacturer = draft.manufacturer
		mode = draft.mode
		panDegrees = draft.panDegrees
		tiltDegrees = draft.tiltDegrees
		invertsPan = draft.invertsPan
		invertsTilt = draft.invertsTilt
	}
	
	var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !channelList.isEmpty }
	
	var mixesWithFlags: Bool { CustomChannel.mixesWithFlags(channelList) }

	var channels: [ProfileChannel] {
		var channels: [ProfileChannel] = []
		
		for (index, channel) in channelList.enumerated() {
			channels.append(ProfileChannel(offset: index + 1, role: channel.role, name: channel.title, isFine: channel.isFine, defaultValue: channel.defaultValue, ranges: channel.ranges))
		}
		
		return channels
	}
	
	var profile: FixtureProfile {
		FixtureProfile(id: identifier, manufacturer: manufacturer, model: name, mode: mode.isEmpty ? "\(channelList.count) channel" : mode, channels: channels, symbol: symbol, mixing: isSubtractive ? .subtractive : .additive, invertsPan: invertsPan, invertsTilt: invertsTilt, panDegrees: panDegrees, tiltDegrees: tiltDegrees)
	}
}
