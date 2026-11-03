import Foundation
import TelegramCore
import AccountContext

func supportSearchAppliesToPane(hasSupportContext: Bool, key: ChatListSearchPaneKey, location: ChatListControllerLocation) -> Bool {
    guard hasSupportContext, key == .chats, case .chatList = location else {
        return false
    }
    return true
}

func supportOneRowPerChat<Row>(_ rows: [Row], peerId: (Row) -> EnginePeer.Id, isRemoved: (Row) -> Bool, shownPeerIds: inout Set<EnginePeer.Id>) -> [Row] {
    var result: [Row] = []
    for row in rows where !isRemoved(row) {
        if shownPeerIds.insert(peerId(row)).inserted {
            result.append(row)
        }
    }
    return result
}

// A message of a migrated group is drawn as its channel.
func supportSearchRowPeer(message: EngineMessage) -> EnginePeer? {
    if let group = message.peers[message.id.peerId] as? TelegramGroup, let migrationReference = group.migrationReference, let channel = message.peers[migrationReference.peerId] {
        return EnginePeer(channel)
    }
    return message.peers[message.id.peerId].flatMap(EnginePeer.init)
}

func supportSearchRowIsMuted(peer: EnginePeer, muteState: EnginePeer.NotificationSettings.MuteState?, privateChatsEnabled: Bool, groupChatsEnabled: Bool, channelsEnabled: Bool, timestamp: Int32) -> Bool {
    switch muteState {
    case let .muted(until):
        return until >= timestamp
    case .unmuted:
        return false
    case .default, .none:
        switch peer {
        case let .channel(channel):
            if case .broadcast = channel.info {
                return !channelsEnabled
            }
            return !groupChatsEnabled
        case .legacyGroup:
            return !groupChatsEnabled
        default:
            return !privateChatsEnabled
        }
    }
}
