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
import AlertUI
import LegacyMediaPickerUI
import SupportTemplates
import TranslateUI
import ChatListUI

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

private let supportChatListBesideOptions: [(value: SupportChatListBeside, title: String)] = [
    (.off, "Off"),
    (.landscape, "In landscape only"),
    (.everywhere, "Everywhere")
]

private final class SupportSettingsControllerArguments {
    let updateSettings: (@escaping (SupportSettings) -> SupportSettings) -> Void
    let selectPeriod: (Int32) -> Void
    let loadMore: (Int32) -> Void
    let importTemplates: () -> Void
    let reloadTemplates: () -> Void
    let setRevealedTemplateFile: (String?, String?) -> Void
    let removeTemplateFile: (String) -> Void
    let openShortcuts: () -> Void

    init(updateSettings: @escaping (@escaping (SupportSettings) -> SupportSettings) -> Void, selectPeriod: @escaping (Int32) -> Void, loadMore: @escaping (Int32) -> Void, importTemplates: @escaping () -> Void, reloadTemplates: @escaping () -> Void, setRevealedTemplateFile: @escaping (String?, String?) -> Void, removeTemplateFile: @escaping (String) -> Void, openShortcuts: @escaping () -> Void) {
        self.updateSettings = updateSettings
        self.selectPeriod = selectPeriod
        self.loadMore = loadMore
        self.importTemplates = importTemplates
        self.reloadTemplates = reloadTemplates
        self.setRevealedTemplateFile = setRevealedTemplateFile
        self.removeTemplateFile = removeTemplateFile
        self.openShortcuts = openShortcuts
    }
}

private enum SupportSettingsSection: Int32 {
    case switching
    case sending
    case order
    case quiet
    case tags
    case beside
    case period
    case loading
    case shortcuts
    case templates
}

private enum SupportSettingsEntry: ItemListNodeEntry {
    enum StableId: Hashable {
        case switchHeader
        case switchBehavior(Int32)
        case sendSilently
        case fixChatsOrder
        case fixChatsOrderInfo
        case automaticMediaDownload
        case inAppNotifications
        case quietInfo
        case trailingTags
        case trailingTagsInfo
        case besideHeader
        case beside(Int32)
        case besideInfo
        case periodHeader
        case period(Int32)
        case periodInfo
        case loadMore
        case loadMoreInfo
        case shortcuts
        case templatesHeader
        case templatesAutocomplete
        case templatesImport
        case templatesReload
        case templatesFile(String)
        case templatesInfo
    }

    case switchHeader(String)
    case switchBehavior(index: Int32, behavior: SupportSwitchBehavior, title: String, isSelected: Bool)
    case sendSilently(String, Bool)
    case fixChatsOrder(String, Bool)
    case fixChatsOrderInfo(String)
    case automaticMediaDownload(String, Bool)
    case inAppNotifications(String, Bool)
    case quietInfo(String)
    case trailingTags(String, Bool)
    case trailingTagsInfo(String)
    case besideHeader(String)
    case beside(index: Int32, value: SupportChatListBeside, title: String, isSelected: Bool)
    case besideInfo(String)
    case periodHeader(String)
    case period(index: Int32, period: Int32, title: String, isSelected: Bool)
    case periodInfo(String)
    case loadMore(title: String, holeTimestamp: Int32?)
    case loadMoreInfo(String)
    case shortcuts(String)
    case templatesHeader(String)
    case templatesAutocomplete(String, Bool)
    case templatesImport(String)
    case templatesReload(title: String, isEnabled: Bool)
    case templatesFile(index: Int32, name: String, info: String, isRevealed: Bool)
    case templatesInfo(String)

    var section: ItemListSectionId {
        switch self {
        case .switchHeader, .switchBehavior:
            return SupportSettingsSection.switching.rawValue
        case .sendSilently:
            return SupportSettingsSection.sending.rawValue
        case .fixChatsOrder, .fixChatsOrderInfo:
            return SupportSettingsSection.order.rawValue
        case .automaticMediaDownload, .inAppNotifications, .quietInfo:
            return SupportSettingsSection.quiet.rawValue
        case .trailingTags, .trailingTagsInfo:
            return SupportSettingsSection.tags.rawValue
        case .besideHeader, .beside, .besideInfo:
            return SupportSettingsSection.beside.rawValue
        case .periodHeader, .period, .periodInfo:
            return SupportSettingsSection.period.rawValue
        case .loadMore, .loadMoreInfo:
            return SupportSettingsSection.loading.rawValue
        case .shortcuts:
            return SupportSettingsSection.shortcuts.rawValue
        case .templatesHeader, .templatesAutocomplete, .templatesImport, .templatesReload, .templatesFile, .templatesInfo:
            return SupportSettingsSection.templates.rawValue
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
        case .fixChatsOrder:
            return .fixChatsOrder
        case .fixChatsOrderInfo:
            return .fixChatsOrderInfo
        case .automaticMediaDownload:
            return .automaticMediaDownload
        case .inAppNotifications:
            return .inAppNotifications
        case .quietInfo:
            return .quietInfo
        case .trailingTags:
            return .trailingTags
        case .trailingTagsInfo:
            return .trailingTagsInfo
        case .besideHeader:
            return .besideHeader
        case let .beside(_, value, _, _):
            return .beside(value.rawValue)
        case .besideInfo:
            return .besideInfo
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
        case .shortcuts:
            return .shortcuts
        case .templatesHeader:
            return .templatesHeader
        case .templatesAutocomplete:
            return .templatesAutocomplete
        case .templatesImport:
            return .templatesImport
        case .templatesReload:
            return .templatesReload
        case let .templatesFile(_, name, _, _):
            return .templatesFile(name)
        case .templatesInfo:
            return .templatesInfo
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
        case .fixChatsOrder:
            return 5
        case .fixChatsOrderInfo:
            return 6
        case .automaticMediaDownload:
            return 7
        case .inAppNotifications:
            return 8
        case .quietInfo:
            return 9
        case .trailingTags:
            return 10
        case .trailingTagsInfo:
            return 11
        case .besideHeader:
            return 12
        case let .beside(index, _, _, _):
            return 13 + index
        case .besideInfo:
            return 16
        case .periodHeader:
            return 17
        case let .period(index, _, _, _):
            return 18 + index
        case .periodInfo:
            return 100
        case .loadMore:
            return 101
        case .loadMoreInfo:
            return 102
        case .shortcuts:
            return 103
        case .templatesHeader:
            return 104
        case .templatesAutocomplete:
            return 105
        case .templatesImport:
            return 106
        case .templatesReload:
            return 107
        case let .templatesFile(index, _, _, _):
            return 108 + index
        case .templatesInfo:
            return Int32.max
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
        case let .fixChatsOrder(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    var settings = settings
                    settings.fixChatsOrder = value
                    return settings
                }
            })
        case let .automaticMediaDownload(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    var settings = settings
                    settings.automaticMediaDownload = value
                    return settings
                }
            })
        case let .inAppNotifications(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    var settings = settings
                    settings.inAppNotifications = value
                    return settings
                }
            })
        case let .trailingTags(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    var settings = settings
                    settings.trailingTags = value
                    return settings
                }
            })
        case let .besideHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .beside(_, value, title, isSelected):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .left, checked: isSelected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.updateSettings { settings in
                    var settings = settings
                    settings.chatListBeside = value
                    return settings
                }
            })
        case let .periodHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .period(_, period, title, isSelected):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .left, checked: isSelected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                if !isSelected {
                    arguments.selectPeriod(period)
                }
            })
        case let .fixChatsOrderInfo(text), let .quietInfo(text), let .trailingTagsInfo(text), let .besideInfo(text), let .periodInfo(text), let .loadMoreInfo(text), let .templatesInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .shortcuts(title):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openShortcuts()
            })
        case let .templatesHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .templatesAutocomplete(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { settings in
                    var settings = settings
                    settings.templatesAutocomplete = value
                    return settings
                }
            })
        case let .templatesImport(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.importTemplates()
            })
        case let .templatesReload(title, isEnabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: isEnabled ? .generic : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                if isEnabled {
                    arguments.reloadTemplates()
                }
            })
        case let .templatesFile(_, name, info, isRevealed):
            return LocalizationListItem(presentationData: presentationData, systemStyle: .glass, id: name, title: name, subtitle: info, checked: false, activity: false, loading: false, editing: LocalizationListItemEditing(editable: true, editing: false, revealed: isRevealed, reorderable: false), sectionId: self.section, alwaysPlain: false, action: {
            }, setItemWithRevealedOptions: { id, fromId in
                arguments.setRevealedTemplateFile(id, fromId)
            }, removeItem: { id in
                arguments.removeTemplateFile(id)
            })
        case let .loadMore(title, holeTimestamp):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: holeTimestamp != nil ? .generic : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                if let holeTimestamp {
                    arguments.loadMore(holeTimestamp)
                }
            })
        }
    }
}

private func supportTemplatesStateSignal(manager: SupportTemplatesManager?) -> Signal<SupportTemplatesState?, NoError> {
    guard let manager else {
        return .single(nil)
    }
    return Signal { subscriber in
        let token = manager.addStateObserver { state in
            subscriber.putNext(state)
        }
        return ActionDisposable {
            manager.removeStateObserver(token)
        }
    }
}

private func supportSettingsEntries(presentationData: PresentationData, settings: SupportSettings, loadState: SupportChatListLoadState, templates: SupportTemplatesState?, revealedTemplateFile: String?, hasHardwareKeyboard: Bool) -> [SupportSettingsEntry] {
    var entries: [SupportSettingsEntry] = []

    entries.append(.switchHeader("AFTER SENDING"))
    for (index, option) in supportSwitchBehaviors.enumerated() {
        entries.append(.switchBehavior(index: Int32(index), behavior: option.behavior, title: option.title, isSelected: option.behavior == settings.switchBehavior))
    }

    entries.append(.sendSilently("Send all messages without sound", settings.sendAllSilently))

    entries.append(.fixChatsOrder("Fix chats order", settings.fixChatsOrder))
    entries.append(.fixChatsOrderInfo("Chats keep their place while messages arrive. Pinning a chat or restarting the app re-sorts the list."))

    entries.append(.automaticMediaDownload("Auto-download media", settings.automaticMediaDownload))
    entries.append(.inAppNotifications("In-app notifications", settings.inAppNotifications))
    entries.append(.quietInfo("These apply to this account only. With auto-download off, media loads when you tap it. With notifications off, new messages play no sound and show no banner while the app is open."))

    entries.append(.trailingTags("Show tags under messages", settings.trailingTags))
    entries.append(.trailingTagsInfo("Hashtags at the end of an incoming message show as tags under it, in one row you can expand. With this off, they stay in the message text."))

    entries.append(.besideHeader("CHAT LIST BESIDE CHATS"))
    for (index, option) in supportChatListBesideOptions.enumerated() {
        entries.append(.beside(index: Int32(index), value: option.value, title: option.title, isSelected: option.value == settings.chatListBeside))
    }
    entries.append(.besideInfo("In landscape, the chat list stays on the left at full height with the open chat beside it. Everywhere also shows a column of chats beside the open chat in portrait, as forums show their topics."))

    entries.append(.periodHeader("LOAD CHATS FOR A PERIOD"))
    for (index, option) in supportChatLoadPeriods.enumerated() {
        entries.append(.period(index: Int32(index), period: option.period, title: option.title, isSelected: option.period == settings.chatLoadPeriod))
    }
    entries.append(.periodInfo("A longer period makes the database larger. A shorter one removes older one-to-one chats from this device at the next launch, and Load more brings them back."))

    switch loadState {
    case .allLoaded:
        break
    case .loading:
        entries.append(.loadMore(title: "Loading chats...", holeTimestamp: nil))
    case let .held(holeTimestamp):
        let date = stringForMediumDate(timestamp: holeTimestamp, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat, withTime: false)
        entries.append(.loadMore(title: "Load more", holeTimestamp: holeTimestamp))
        entries.append(.loadMoreInfo("Chats are loaded back to \(date)."))
    }

    if hasHardwareKeyboard {
        entries.append(.shortcuts("Keyboard Shortcuts"))
    }

    if let templates {
        entries.append(.templatesHeader("TEMPLATES"))
        entries.append(.templatesAutocomplete("Enable templates autocomplete", settings.templatesAutocomplete))
        entries.append(.templatesImport("Import Template Files"))
        entries.append(.templatesReload(title: templates.isReloading ? "Reloading..." : "Reload Templates", isEnabled: !templates.isReloading))
        for (index, file) in templates.files.enumerated() {
            var info = file.templateCount == 1 ? "1 template" : "\(file.templateCount) templates"
            if file.hasUrl {
                info += ", updates from its URL"
            }
            entries.append(.templatesFile(index: Int32(index), name: file.name, info: info, isRevealed: file.name == revealedTemplateFile))
        }
        if templates.errors.isEmpty {
            entries.append(.templatesInfo("With autocomplete on, Tab and the composer button open the templates panel. With it off, they replace the key before the caret with its answer, and the button opens the panel if no key matches.\n\nImport tl_*.txt files. A file with a {URL} updates from it at each launch and on reload, keeps your keys, and lists its changes in the Telegram chat."))
        } else {
            entries.append(.templatesInfo("Last reload:\n\n" + templates.errors.joined(separator: "\n\n")))
        }
    }

    return entries
}

public func supportSettingsController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?

    let showTemplatesResult: (SupportTemplatesReloadResult, String) -> Void = { result, successText in
        supportPresentTemplatesReloadResult(context: context, result: result, successText: successText, elevatedLayout: false, present: { controller in
            presentControllerImpl?(controller, nil)
        })
    }

    let revealedTemplateFile = Atomic<String?>(value: nil)
    let revealedTemplateFilePromise = ValuePromise<String?>(nil, ignoreRepeated: true)

    let setPeriod: (Int32) -> Void = { period in
        let _ = updateSupportSettingsInteractively(engine: context.engine, { settings in
            var settings = settings
            settings.chatLoadPeriod = period
            return settings
        }).startStandalone()
    }

    let arguments = SupportSettingsControllerArguments(updateSettings: { f in
        let _ = updateSupportSettingsInteractively(engine: context.engine, f).startStandalone()
    }, selectPeriod: { period in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let title: String
        let text: String
        let actionTitle: String
        let actionType: TextAlertActionType
        if period == SupportSettings.allChatsLoadPeriod {
            title = "Load All Chats?"
            text = "This loads every chat this account has ever had, with no time limit. On a support account that can be a very large number of chats: loading can take a long time, use a lot of data and make the database on this device much larger.\n\nChoose a shorter period unless you really need all of them. Switching back later removes older one-to-one chats from this device at the next launch."
            actionTitle = "Load All"
            actionType = .destructiveAction
        } else if period >= 30 * 24 * 60 * 60 {
            let unit = period >= 365 * 24 * 60 * 60 ? "year" : "month"
            title = "Load Chats for 1 \(unit.capitalized)?"
            text = "This loads every chat with activity in the last \(unit). On a busy support account that can be many chats: loading takes a while, uses data and makes the database on this device larger."
            actionTitle = "Load"
            actionType = .defaultAction
        } else {
            setPeriod(period)
            return
        }
        presentControllerImpl?(textAlertController(context: context, title: title, text: text, actions: [TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {
        }), TextAlertAction(type: actionType, title: actionTitle, action: {
            setPeriod(period)
        })]), nil)
    }, loadMore: { holeTimestamp in
        context.supportContext?.loadMoreChats(holeTimestamp: holeTimestamp)
    }, importTemplates: {
        guard let manager = context.supportTemplates else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentControllerImpl?(legacyICloudFilePicker(theme: presentationData.theme, mode: .import, hasMultiselection: true, documentTypes: ["public.plain-text"], completion: { urls in
            if urls.isEmpty {
                return
            }
            manager.importFiles(urls, completion: { result in
                showTemplatesResult(result, "Templates imported.")
            })
        }), nil)
    }, reloadTemplates: {
        context.supportTemplates?.reload(completion: { result in
            showTemplatesResult(result, "Templates reloaded!")
        })
    }, setRevealedTemplateFile: { id, fromId in
        let updated = revealedTemplateFile.modify { current in
            if (id == nil && fromId == current) || (id != nil && fromId == nil) {
                return id
            }
            return current
        }
        revealedTemplateFilePromise.set(updated)
    }, removeTemplateFile: { name in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentControllerImpl?(textAlertController(context: context, title: nil, text: "Remove '\(name)' and its previous version from this device?", actions: [TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {
        }), TextAlertAction(type: .destructiveAction, title: "Remove", action: {
            context.supportTemplates?.removeFile(name: name)
        })]), nil)
    }, openShortcuts: {
        pushControllerImpl?(supportShortcutsController(context: context))
    })

    let settings = context.engine.data.subscribe(TelegramEngine.EngineData.Item.Configuration.ApplicationSpecificPreference(key: PreferencesKeys.supportSettings))
    |> map { entry -> SupportSettings in
        return entry?.get(SupportSettings.self) ?? .default
    }

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        settings,
        context.engine.messages.supportChatListLoadState(),
        supportTemplatesStateSignal(manager: context.supportTemplates),
        revealedTemplateFilePromise.get(),
        supportHardwareKeyboardIsConnected()
    )
    |> map { presentationData, settings, loadState, templates, revealedTemplateFile, hasHardwareKeyboard -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Support Settings"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: true)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: supportSettingsEntries(presentationData: presentationData, settings: settings, loadState: loadState, templates: templates, revealedTemplateFile: revealedTemplateFile, hasHardwareKeyboard: hasHardwareKeyboard), style: .blocks)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c, a in
        controller?.present(c, in: .window(.root), with: a)
    }
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
    }
    return controller
}
