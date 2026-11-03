import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import TelegramStringFormatting

private let supportChatLoadPeriods: [(period: Int32, title: String)] = [
    (1 * 24 * 60 * 60, "1 day"),
    (7 * 24 * 60 * 60, "1 week"),
    (30 * 24 * 60 * 60, "1 month"),
    (365 * 24 * 60 * 60, "1 year"),
    (SupportSettings.allChatsLoadPeriod, "All of them")
]

private let supportSwitchBehaviors: [(behavior: SupportSwitchBehavior, title: String)] = [
    (.none, "Just send the reply"),
    (.next, "Send and switch to next"),
    (.previous, "Send and switch to previous")
]

private final class SupportSettingsControllerArguments {
    let updateSettings: (@escaping (SupportSettings) -> SupportSettings) -> Void
    let loadMore: (Int32) -> Void

    init(updateSettings: @escaping (@escaping (SupportSettings) -> SupportSettings) -> Void, loadMore: @escaping (Int32) -> Void) {
        self.updateSettings = updateSettings
        self.loadMore = loadMore
    }
}

private enum SupportSettingsSection: Int32 {
    case switching
    case sending
    case period
    case loading
}

private enum SupportSettingsEntry: ItemListNodeEntry {
    enum StableId: Hashable {
        case switchHeader
        case switchBehavior(Int32)
        case sendSilently
        case periodHeader
        case period(Int32)
        case periodInfo
        case loadMore
        case loadMoreInfo
    }

    case switchHeader(String)
    case switchBehavior(index: Int32, behavior: SupportSwitchBehavior, title: String, isSelected: Bool)
    case sendSilently(String, Bool)
    case periodHeader(String)
    case period(index: Int32, period: Int32, title: String, isSelected: Bool)
    case periodInfo(String)
    case loadMore(title: String, holeTimestamp: Int32?)
    case loadMoreInfo(String)

    var section: ItemListSectionId {
        switch self {
        case .switchHeader, .switchBehavior:
            return SupportSettingsSection.switching.rawValue
        case .sendSilently:
            return SupportSettingsSection.sending.rawValue
        case .periodHeader, .period, .periodInfo:
            return SupportSettingsSection.period.rawValue
        case .loadMore, .loadMoreInfo:
            return SupportSettingsSection.loading.rawValue
        }
    }

    var stableId: StableId {
        switch self {
        case .switchHeader:
            return .switchHeader
        case let .switchBehavior(_, behavior, _, _):
            return .switchBehavior(behavior.rawValue)
        case .sendSilently:
            return .sendSilently
        case .periodHeader:
            return .periodHeader
        case let .period(_, period, _, _):
            return .period(period)
        case .periodInfo:
            return .periodInfo
        case .loadMore:
            return .loadMore
        case .loadMoreInfo:
            return .loadMoreInfo
        }
    }

    var sortIndex: Int32 {
        switch self {
        case .switchHeader:
            return 0
        case let .switchBehavior(index, _, _, _):
            return 1 + index
        case .sendSilently:
            return 4
        case .periodHeader:
            return 5
        case let .period(index, _, _, _):
            return 6 + index
        case .periodInfo:
            return 100
        case .loadMore:
            return 101
        case .loadMoreInfo:
            return 102
        }
    }

    static func <(lhs: SupportSettingsEntry, rhs: SupportSettingsEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! SupportSettingsControllerArguments
        switch self {
        case let .switchHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .switchBehavior(_, behavior, title, isSelected):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .left, checked: isSelected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.updateSettings { settings in
                    var settings = settings
                    settings.switchBehavior = behavior
                    return settings
                }
            })
        case let .sendSilently(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    var settings = settings
                    settings.sendAllSilently = value
                    return settings
                }
            })
        case let .periodHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .period(_, period, title, isSelected):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .left, checked: isSelected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.updateSettings { settings in
                    var settings = settings
                    settings.chatLoadPeriod = period
                    return settings
                }
            })
        case let .periodInfo(text), let .loadMoreInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .loadMore(title, holeTimestamp):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: holeTimestamp != nil ? .generic : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                if let holeTimestamp {
                    arguments.loadMore(holeTimestamp)
                }
            })
        }
    }
}

private func supportSettingsEntries(presentationData: PresentationData, settings: SupportSettings, loadState: SupportChatListLoadState) -> [SupportSettingsEntry] {
    var entries: [SupportSettingsEntry] = []

    entries.append(.switchHeader("AFTER SENDING"))
    for (index, option) in supportSwitchBehaviors.enumerated() {
        entries.append(.switchBehavior(index: Int32(index), behavior: option.behavior, title: option.title, isSelected: option.behavior == settings.switchBehavior))
    }

    entries.append(.sendSilently("Send all messages without sound", settings.sendAllSilently))

    entries.append(.periodHeader("LOAD CHATS FOR A PERIOD"))
    for (index, option) in supportChatLoadPeriods.enumerated() {
        entries.append(.period(index: Int32(index), period: option.period, title: option.title, isSelected: option.period == settings.chatLoadPeriod))
    }
    entries.append(.periodInfo("A longer period makes the database larger. A shorter one removes older one-to-one chats from this device at the next launch, and Load more brings them back."))

    switch loadState {
    case .allLoaded:
        break
    case .loading:
        entries.append(.loadMore(title: "Loading...", holeTimestamp: nil))
    case let .held(holeTimestamp):
        let date = stringForMediumDate(timestamp: holeTimestamp, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat, withTime: false)
        entries.append(.loadMore(title: "Load more", holeTimestamp: holeTimestamp))
        entries.append(.loadMoreInfo("Chats are loaded back to \(date)."))
    }

    return entries
}

public func supportSettingsController(context: AccountContext) -> ViewController {
    let arguments = SupportSettingsControllerArguments(updateSettings: { f in
        let _ = updateSupportSettingsInteractively(engine: context.engine, f).startStandalone()
    }, loadMore: { holeTimestamp in
        context.supportContext?.loadMoreChats(holeTimestamp: holeTimestamp)
    })

    let settings = context.engine.data.subscribe(TelegramEngine.EngineData.Item.Configuration.ApplicationSpecificPreference(key: PreferencesKeys.supportSettings))
    |> map { entry -> SupportSettings in
        return entry?.get(SupportSettings.self) ?? .default
    }

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        settings,
        context.engine.messages.supportChatListLoadState()
    )
    |> map { presentationData, settings, loadState -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Support Settings"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: true)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: supportSettingsEntries(presentationData: presentationData, settings: settings, loadState: loadState), style: .blocks)

        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
