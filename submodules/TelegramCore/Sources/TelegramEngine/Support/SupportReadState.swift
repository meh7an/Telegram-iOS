import Foundation
import Postbox
import SwiftSignalKit

private let deletedUserSweepStartDelay: Double = 30.0
private let deletedUserSweepBatchCount = 50
private let deletedUserSweepBatchPause: Double = 0.05

public func supportOpensChatAtEnd(isSupportUser: Bool, hasTag: Bool, peerId: PeerId?, accountPeerId: PeerId) -> Bool {
    guard isSupportUser, !hasTag, let peerId else {
        return false
    }
    return peerId != accountPeerId
}

enum SupportSendReadTarget: Equatable {
    case chat
    case thread(Int64)
}

struct SupportSendReadInfo {
    var isDeferred: Bool
    var threadId: Int64?
    var replyThreadId: Int64?
}

public func supportSendIsDeferred(attributes: [EngineMessage.Attribute]) -> Bool {
    return attributes.contains(where: { $0 is OutgoingScheduleInfoMessageAttribute || $0 is OutgoingQuickReplyMessageAttribute })
}

func supportSendReadTargets(peerHasThreads: Bool, sends: [SupportSendReadInfo]) -> [SupportSendReadTarget] {
    var result: [SupportSendReadTarget] = []
    for send in sends where !send.isDeferred {
        let target: SupportSendReadTarget
        if peerHasThreads, let threadId = send.threadId ?? send.replyThreadId {
            target = .thread(threadId)
        } else {
            target = .chat
        }
        if !result.contains(target) {
            result.append(target)
        }
    }
    return result
}

func supportSendReadInfo(transaction: Transaction, message: EnqueueMessage) -> SupportSendReadInfo {
    let threadId: Int64?
    var replyThreadId: Int64?
    switch message {
    case let .message(_, _, _, _, threadIdValue, replyToMessageId, _, _, _, _):
        threadId = threadIdValue
        if let replyToMessageId {
            replyThreadId = transaction.getMessage(replyToMessageId.messageId)?.threadId
        }
    case let .forward(_, threadIdValue, _, _, _):
        threadId = threadIdValue
    }
    return SupportSendReadInfo(isDeferred: supportSendIsDeferred(attributes: message.attributes), threadId: threadId, replyThreadId: replyThreadId)
}

func supportApplyReadOnSend(transaction: Transaction, network: Network, stateManager: AccountStateManager, peerId: PeerId, sends: [SupportSendReadInfo]) {
    let peerHasThreads = transaction.getPeer(peerId)?.isForumOrMonoForum ?? false
    for target in supportSendReadTargets(peerHasThreads: peerHasThreads, sends: sends) {
        switch target {
        case .chat:
            let namespace = peerId.namespace == Namespaces.Peer.SecretChat ? Namespaces.Message.SecretIncoming : Namespaces.Message.Cloud
            if let index = transaction.getTopPeerMessageIndex(peerId: peerId, namespace: namespace) {
                _internal_applyMaxReadIndexInteractively(transaction: transaction, stateManager: stateManager, index: index)
            }
        case let .thread(threadId):
            _internal_toggleForumThreadUnreadMarkInteractively(transaction: transaction, network: network, peerId: peerId, threadId: threadId, setToValue: false)
        }
    }
}

// The id the unread divider goes above the next incoming message after. It is known before that message
// arrives, so the two land in one list update and slide in together. A chat that keeps no read state never gets one.
func supportUnreadDividerBoundary(state: CombinedPeerReadState?, topMessageId: Int32?) -> Int32? {
    guard let state else {
        return nil
    }
    for (namespace, value) in state.states where namespace == Namespaces.Message.Cloud {
        guard case let .idBased(maxIncomingReadId, _, maxKnownId, _, _) = value else {
            continue
        }
        if value.isUnread {
            return maxIncomingReadId
        }
        if maxKnownId >= Int32.max - 1 {
            return Int32.max
        }
        return max(maxIncomingReadId, topMessageId ?? 0)
    }
    return nil
}

func _internal_supportUnreadDividerBoundary(account: Account, peerId: PeerId) -> Signal<Int32?, NoError> {
    let key = PostboxViewKey.combinedReadState(peerId: peerId, handleThreads: true)
    let postbox = account.postbox
    return postbox.combinedView(keys: [key])
    |> mapToSignal { views -> Signal<Int32?, NoError> in
        let state = (views.views[key] as? CombinedReadStateView)?.state
        return postbox.transaction { transaction -> Int32? in
            return supportUnreadDividerBoundary(state: state, topMessageId: transaction.getTopPeerMessageIndex(peerId: peerId, namespace: Namespaces.Message.Cloud)?.id.id)
        }
    }
    |> distinctUntilChanged
}

// TDesktop's History::clearUnreadOnClientSide: a deleted user's chat keeps no unread state on a support account.
func supportClearsUnread(isSupportAccount: Bool, peer: Peer?) -> Bool {
    return isSupportAccount && (peer?.isDeleted ?? false)
}

func supportClearsUnread(transaction: Transaction, accountPeerId: PeerId, peerId: PeerId) -> Bool {
    guard peerId.namespace == Namespaces.Peer.CloudUser, transaction.getPeer(peerId)?.isDeleted ?? false else {
        return false
    }
    return isSupportAccount(transaction: transaction, accountPeerId: accountPeerId)
}

// `maxKnownId` keeps an incoming message from being counted, as in `nonMemberChannelReadState`.
func supportClearedReadState(current: PeerReadState?, topMessageId: Int32?) -> PeerReadState {
    var maxIncomingReadId = topMessageId ?? 0
    var maxOutgoingReadId: Int32 = 0
    if case let .idBased(currentMaxIncomingReadId, currentMaxOutgoingReadId, _, _, _) = current {
        maxIncomingReadId = max(maxIncomingReadId, currentMaxIncomingReadId)
        maxOutgoingReadId = currentMaxOutgoingReadId
    }
    return .idBased(maxIncomingReadId: maxIncomingReadId, maxOutgoingReadId: maxOutgoingReadId, maxKnownId: Int32.max - 1, count: 0, markedUnread: false)
}

func readStateOperationTargetsDeletedUser(_ operation: AccountStateMutationOperation, getPeer: (PeerId) -> Peer?) -> Bool {
    guard let peerId = readStateOperationPeerId(operation), peerId.namespace == Namespaces.Peer.CloudUser else {
        return false
    }
    return getPeer(peerId)?.isDeleted ?? false
}

func supportReadStatesToStore(transaction: Transaction, accountPeerId: PeerId, readStates: [PeerId: [MessageId.Namespace: PeerReadState]]) -> [PeerId: [MessageId.Namespace: PeerReadState]] {
    var result = readStates
    for (peerId, states) in readStates where supportClearsUnread(transaction: transaction, accountPeerId: accountPeerId, peerId: peerId) {
        let topMessageId = transaction.getTopPeerMessageIndex(peerId: peerId, namespace: Namespaces.Message.Cloud)?.id.id
        result[peerId] = [Namespaces.Message.Cloud: supportClearedReadState(current: states[Namespaces.Message.Cloud], topMessageId: topMessageId)]
    }
    return result
}

private func supportDeletedUserSweepBatch(transaction: Transaction, groupId: PeerGroupId, accountPeerId: PeerId, position: (index: ChatListIndex, isChat: Bool)?) -> (next: (index: ChatListIndex, isChat: Bool)?, clearedCount: Int) {
    let entries = transaction.chatListStoredEntries(groupId: groupId, earlierThan: position, count: deletedUserSweepBatchCount)
    var next: (index: ChatListIndex, isChat: Bool)?
    var clearedCount = 0
    for entry in entries {
        switch entry {
        case let .hole(hole):
            next = (ChatListIndex(pinningIndex: nil, messageIndex: hole.index), false)
        case let .chat(index):
            next = (index, true)
            let peerId = index.messageIndex.id.peerId
            guard supportClearsUnread(transaction: transaction, accountPeerId: accountPeerId, peerId: peerId), let current = transaction.getPeerReadStates(peerId)?.first(where: { $0.0 == Namespaces.Message.Cloud })?.1 else {
                continue
            }
            let cleared = supportClearedReadState(current: current, topMessageId: transaction.getTopPeerMessageIndex(peerId: peerId, namespace: Namespaces.Message.Cloud)?.id.id)
            if cleared != current {
                transaction.resetIncomingReadStates([peerId: [Namespaces.Message.Cloud: cleared]])
                clearedCount += 1
            }
        }
    }
    return (next, clearedCount)
}

func managedSupportDeletedUserSweep(postbox: Postbox, accountPeerId: PeerId) -> Signal<Never, NoError> {
    let groupIds: [PeerGroupId] = [.root, Namespaces.PeerGroup.archive]

    func step(groupIndex: Int, position: (index: ChatListIndex, isChat: Bool)?, clearedCount: Int) -> Signal<Never, NoError> {
        if groupIndex >= groupIds.count {
            Logger.shared.log("SupportReadState", "cleared \(clearedCount) deleted users' read states")
            return .complete()
        }
        return postbox.transaction { transaction in
            return supportDeletedUserSweepBatch(transaction: transaction, groupId: groupIds[groupIndex], accountPeerId: accountPeerId, position: position)
        }
        |> mapToSignal { result -> Signal<Never, NoError> in
            let following: Signal<Never, NoError>
            if let next = result.next {
                following = step(groupIndex: groupIndex, position: next, clearedCount: clearedCount + result.clearedCount)
            } else {
                following = step(groupIndex: groupIndex + 1, position: nil, clearedCount: clearedCount + result.clearedCount)
            }
            return Signal<Never, NoError>.complete()
            |> delay(deletedUserSweepBatchPause, queue: Queue.concurrentDefaultQueue())
            |> then(following)
        }
    }

    return Signal<Never, NoError>.complete()
    |> delay(deletedUserSweepStartDelay, queue: Queue.concurrentDefaultQueue())
    |> then(step(groupIndex: 0, position: nil, clearedCount: 0))
}
