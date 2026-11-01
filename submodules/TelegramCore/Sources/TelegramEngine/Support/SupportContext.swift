import Foundation
import SwiftSignalKit

private let supportChatListLoadPeriod: Int32 = 7 * 24 * 60 * 60

public final class SupportContext {
    private let currentChatListLoadTill: Atomic<Int32>
    private let chatListLoadTillPromise: ValuePromise<Int32>
    
    public var chatListLoadTill: Signal<Int32, NoError> {
        return self.chatListLoadTillPromise.get()
    }
    
    public init() {
        let loadTill = supportChatListInitialLoadTill(now: Int32(Date().timeIntervalSince1970), period: supportChatListLoadPeriod)
        self.currentChatListLoadTill = Atomic(value: loadTill)
        self.chatListLoadTillPromise = ValuePromise(loadTill, ignoreRepeated: true)
    }
    
    public func loadMoreChats(holeTimestamp: Int32) {
        let loadTill = self.currentChatListLoadTill.modify { current in
            return supportChatListLoadTillAfterLoadMore(current: current, holeTimestamp: holeTimestamp, period: supportChatListLoadPeriod)
        }
        self.chatListLoadTillPromise.set(loadTill)
    }
}
