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
import UndoUI

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
    let importTemplates: () -> Void
    let reloadTemplates: () -> Void
    let setRevealedTemplateFile: (String?, String?) -> Void
    let removeTemplateFile: (String) -> Void

    init(updateSettings: @escaping (@escaping (SupportSettings) -> SupportSettings) -> Void, loadMore: @escaping (Int32) -> Void, importTemplates: @escaping () -> Void, reloadTemplates: @escaping () -> Void, setRevealedTemplateFile: @escaping (String?, String?) -> Void, removeTemplateFile: @escaping (String) -> Void) {
        self.updateSettings = updateSettings
        self.loadMore = loadMore
        self.importTemplates = importTemplates
        self.reloadTemplates = reloadTemplates
        self.setRevealedTemplateFile = setRevealedTemplateFile
        self.removeTemplateFile = removeTemplateFile
    }
}

private enum SupportSettingsSection: Int32 {
    case switching
    case sending
    case period
    case loading
    case templates
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
        case templatesHeader
        case templatesImport
        case templatesReload
        case templatesFile(String)
        case templatesInfo
    }

    case switchHeader(String)
    case switchBehavior(index: Int32, behavior: SupportSwitchBehavior, title: String, isSelected: Bool)
    case sendSilently(String, Bool)
    case periodHeader(String)
    case period(index: Int32, period: Int32, title: String, isSelected: Bool)
    case periodInfo(String)
    case loadMore(title: String, holeTimestamp: Int32?)
    case loadMoreInfo(String)
    case templatesHeader(String)
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
        case .periodHeader, .period, .periodInfo:
            return SupportSettingsSection.period.rawValue
        case .loadMore, .loadMoreInfo:
            return SupportSettingsSection.loading.rawValue
        case .templatesHeader, .templatesImport, .templatesReload, .templatesFile, .templatesInfo:
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
        case .templatesHeader:
            return .templatesHeader
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
        case .templatesHeader:
            return 103
        case .templatesImport:
            return 104
        case .templatesReload:
            return 105
        case let .templatesFile(index, _, _, _):
            return 106 + index
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
        case let .periodInfo(text), let .loadMoreInfo(text), let .templatesInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .templatesHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
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

private func supportSettingsEntries(presentationData: PresentationData, settings: SupportSettings, loadState: SupportChatListLoadState, templates: SupportTemplatesState?, revealedTemplateFile: String?) -> [SupportSettingsEntry] {
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

    if let templates {
        entries.append(.templatesHeader("TEMPLATES"))
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
            entries.append(.templatesInfo("Import tl_*.txt files. A file with a {URL} updates from it at each launch and on reload, keeps your keys, and lists its changes in the Telegram chat."))
        } else {
            entries.append(.templatesInfo("Last reload:\n\n" + templates.errors.joined(separator: "\n\n")))
        }
    }

    return entries
}

public func supportSettingsController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?

    let showTemplatesResult: (SupportTemplatesReloadResult, String) -> Void = { result, successText in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        var updated: String?
        if !result.updatedFiles.isEmpty {
            updated = "Updated: \(result.updatedFiles.joined(separator: ", ")). The changes are in the Telegram chat."
        }
        if result.errors.isEmpty {
            let text = updated.flatMap { "\(successText) \($0)" } ?? successText
            presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in
                return false
            }), nil)
        } else {
            let text = (result.errors + (updated.flatMap { [$0] } ?? [])).joined(separator: "\n\n")
            presentControllerImpl?(textAlertController(context: context, title: "Errors", text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {
            })]), nil)
        }
    }

    let revealedTemplateFile = Atomic<String?>(value: nil)
    let revealedTemplateFilePromise = ValuePromise<String?>(nil, ignoreRepeated: true)

    let arguments = SupportSettingsControllerArguments(updateSettings: { f in
        let _ = updateSupportSettingsInteractively(engine: context.engine, f).startStandalone()
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
        revealedTemplateFilePromise.get()
    )
    |> map { presentationData, settings, loadState, templates, revealedTemplateFile -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Support Settings"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: true)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: supportSettingsEntries(presentationData: presentationData, settings: settings, loadState: loadState, templates: templates, revealedTemplateFile: revealedTemplateFile), style: .blocks)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c, a in
        controller?.present(c, in: .window(.root), with: a)
    }
    return controller
}
