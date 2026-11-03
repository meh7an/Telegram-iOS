import Foundation
import Postbox
import SwiftSignalKit
internal import TelegramApi

struct SupportInstallationTag: Codable, Equatable {
    var value: Int64
}

public struct SupportUserInfo: Equatable {
    public let author: String
    public let date: Int32
    public let text: String
    public let entities: [MessageTextEntity]

    public init(author: String, date: Int32, text: String, entities: [MessageTextEntity]) {
        self.author = author
        self.date = date
        self.text = text
        self.entities = entities
    }
}

public enum SaveSupportUserInfoError {
    case generic
}

func supportInstallationTag(transaction: Transaction) -> UInt64 {
    if let stored = transaction.getPreferencesEntry(key: PreferencesKeys.supportInstallationTag)?.get(SupportInstallationTag.self) {
        return UInt64(bitPattern: stored.value)
    }
    var value = Int64.random(in: Int64.min ... Int64.max)
    while value & 0xffffffff == 0 {
        value = Int64.random(in: Int64.min ... Int64.max)
    }
    transaction.updatePreferencesEntry(key: PreferencesKeys.supportInstallationTag, { _ in
        return PreferencesEntry(SupportInstallationTag(value: value))
    })
    return UInt64(bitPattern: value)
}

func supportNameFallback(installationTag: UInt64) -> String {
    return "[rand^\(installationTag)]"
}

func supportName(_ result: Api.help.SupportName) -> String {
    switch result {
    case let .supportName(data):
        return data.name
    }
}

func supportUserInfo(_ result: Api.help.UserInfo) -> SupportUserInfo? {
    switch result {
    case .userInfoEmpty:
        return nil
    case let .userInfo(data):
        if data.message.isEmpty {
            return nil
        }
        return SupportUserInfo(author: data.author, date: data.date, text: data.message, entities: messageTextEntitiesFromApiEntities(data.entities))
    }
}

func supportTrimmedUserInfoText(text: String, entities: [MessageTextEntity]) -> (text: String, entities: [MessageTextEntity]) {
    let utf16 = Array(text.utf16)
    let isWhitespace: (UInt16) -> Bool = { unit in
        return Unicode.Scalar(unit).flatMap(CharacterSet.whitespacesAndNewlines.contains) ?? false
    }
    var start = 0
    while start < utf16.count && isWhitespace(utf16[start]) {
        start += 1
    }
    var end = utf16.count
    while end > start && isWhitespace(utf16[end - 1]) {
        end -= 1
    }
    let trimmedEntities = entities.compactMap { entity -> MessageTextEntity? in
        let lowerBound = max(entity.range.lowerBound, start) - start
        let upperBound = min(entity.range.upperBound, end) - start
        if lowerBound >= upperBound {
            return nil
        }
        var entity = entity
        entity.range = lowerBound ..< upperBound
        return entity
    }
    return (String(decoding: utf16[start ..< end], as: UTF16.self), trimmedEntities)
}

func _internal_supportName(network: Network, postbox: Postbox) -> Signal<String, NoError> {
    return network.request(Api.functions.help.getSupportName())
    |> map(Optional.init)
    |> `catch` { _ -> Signal<Api.help.SupportName?, NoError> in
        return .single(nil)
    }
    |> mapToSignal { result -> Signal<String, NoError> in
        if let result {
            return .single(supportName(result))
        }
        return postbox.transaction { transaction -> String in
            return supportNameFallback(installationTag: supportInstallationTag(transaction: transaction))
        }
    }
}

func _internal_refreshSupportUserInfo(account: Account, peerId: PeerId) -> Signal<Never, NoError> {
    guard let supportContext = account.supportContext else {
        return .complete()
    }
    return account.postbox.transaction { transaction -> Api.InputUser? in
        return transaction.getPeer(peerId).flatMap(apiInputUser)
    }
    |> mapToSignal { inputUser -> Signal<Never, NoError> in
        guard let inputUser else {
            return .complete()
        }
        return account.network.request(Api.functions.help.getUserInfo(userId: inputUser))
        |> map(Optional.init)
        |> `catch` { _ -> Signal<Api.help.UserInfo?, NoError> in
            return .single(nil)
        }
        |> mapToSignal { result -> Signal<Never, NoError> in
            if let result {
                supportContext.applyUserInfo(peerId: peerId, info: supportUserInfo(result))
            }
            return .complete()
        }
    }
}

func _internal_saveSupportUserInfo(account: Account, peerId: PeerId, text: String, entities: [MessageTextEntity]) -> Signal<Never, SaveSupportUserInfoError> {
    guard let supportContext = account.supportContext else {
        return .fail(.generic)
    }
    let trimmed = supportTrimmedUserInfoText(text: text, entities: entities)
    return account.postbox.transaction { transaction -> (Api.InputUser, [Api.MessageEntity])? in
        guard let inputUser = transaction.getPeer(peerId).flatMap(apiInputUser) else {
            return nil
        }
        var associatedPeers = SimpleDictionary<PeerId, Peer>()
        for entity in trimmed.entities {
            if case let .TextMention(mentionedPeerId) = entity.type, let peer = transaction.getPeer(mentionedPeerId) {
                associatedPeers[peer.id] = peer
            }
        }
        return (inputUser, apiEntitiesFromMessageTextEntities(trimmed.entities, associatedPeers: associatedPeers))
    }
    |> castError(SaveSupportUserInfoError.self)
    |> mapToSignal { parameters -> Signal<Never, SaveSupportUserInfoError> in
        guard let (inputUser, apiEntities) = parameters else {
            return .fail(.generic)
        }
        let request = account.network.request(Api.functions.help.editUserInfo(userId: inputUser, message: trimmed.text, entities: apiEntities))
        |> mapError { _ -> SaveSupportUserInfoError in
            return .generic
        }
        |> map { result -> SupportUserInfo? in
            return supportUserInfo(result)
        }
        return supportContext.saveUserInfo(peerId: peerId, text: trimmed.text, entities: trimmed.entities, request: request)
    }
}
