import SwiftData
import SwiftUI

struct CustomChannel: Codable, Hashable, Identifiable {
    var role: ChannelRole = .custom
    var name: String = ""

    var id: String { "\(role.rawValue)-\(name)" }
}

@Model
final class CustomProfile {
    var identifier: String = UUID().uuidString
    var name: String = ""
    var symbol: String = "lightbulb"
    var channelList: [CustomChannel] = []
    var createdAt: Date = Date.now

    init(name: String, symbol: String, channels: [CustomChannel]) {
        identifier = "custom-\(UUID().uuidString)"
        self.name = name
        self.symbol = symbol
        channelList = channels
        createdAt = .now
    }

    var profile: FixtureProfile {
        FixtureProfile(
            id: identifier,
            model: name,
            mode: "\(channelList.count) channel",
            channels: channelList.enumerated().map { index, channel in
                ProfileChannel(
                    offset: index + 1,
                    role: channel.role,
                    name: channel.name.isEmpty ? channel.role.name : channel.name
                )
            },
            symbol: symbol
        )
    }
}
