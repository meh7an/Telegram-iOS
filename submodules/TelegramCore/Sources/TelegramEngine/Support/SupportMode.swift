import Foundation

public func isSupportAccountPhone(_ phone: String?) -> Bool {
    guard let phone else {
        return false
    }
    return phone.hasPrefix("424")
}

func resolvedIsSupportUser(storedPhone: String?, recordAttribute: Bool) -> Bool {
    if let storedPhone {
        return isSupportAccountPhone(storedPhone)
    }
    return recordAttribute
}

public func supportModeWasLost(phone: String?, isSupportUser: Bool) -> Bool {
    return !isSupportUser && isSupportAccountPhone(phone)
}

public func supportChatListHoleIsHeld(holeTimestamp: Int32, loadTill: Int32) -> Bool {
    return holeTimestamp <= loadTill
}

func supportChatListInitialLoadTill(now: Int32, period: Int32) -> Int32 {
    return max(now - period, 0)
}

func supportChatListLoadTillAfterLoadMore(current: Int32, holeTimestamp: Int32, period: Int32) -> Int32 {
    return max(min(current, holeTimestamp - period), 0)
}
