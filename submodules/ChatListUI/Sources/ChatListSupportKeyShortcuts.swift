import Foundation
import UIKit
import AccountContext
import Display
import PresentationDataUtils
import SupportTemplates
import SwiftSignalKit
import TelegramCore
import UndoUI

public func supportPresentTemplatesReloadResult(context: AccountContext, result: SupportTemplatesReloadResult, successText: String, elevatedLayout: Bool, present: @escaping (ViewController) -> Void) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    var updated: String?
    if !result.updatedFiles.isEmpty {
        updated = "Updated: \(result.updatedFiles.joined(separator: ", ")). The changes are in the Telegram chat."
    }
    if result.errors.isEmpty {
        let text = updated.flatMap { "\(successText) \($0)" } ?? successText
        present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: elevatedLayout, action: { _ in
            return false
        }))
    } else {
        let text = (result.errors + (updated.flatMap { [$0] } ?? [])).joined(separator: "\n\n")
        present(textAlertController(context: context, title: "Errors", text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {
        })]))
    }
}

public func supportReloadTemplatesAction(context: AccountContext, present: @escaping (ViewController) -> Void) -> () -> Void {
    guard let supportContext = context.supportContext, let manager = context.supportTemplates else {
        return {}
    }
    let reload: () -> Void = {
        guard supportContext.allowsHardwarePress(of: .reloadTemplates) else {
            return
        }
        manager.reload(completion: { result in
            Queue.mainQueue().async {
                supportPresentTemplatesReloadResult(context: context, result: result, successText: "Templates reloaded!", elevatedLayout: true, present: present)
            }
        })
    }
    return reload
}

public func supportTemplatesReloadKeyShortcuts(context: AccountContext, present: @escaping (ViewController) -> Void) -> [KeyShortcut] {
    guard let supportContext = context.supportContext else {
        return []
    }
    return supportKeyShortcuts(combos: supportContext.shortcutCombos(.reloadTemplates), title: supportShortcutTitle(.reloadTemplates), perform: supportReloadTemplatesAction(context: context, present: present))
}

public func supportShortcutTitle(_ action: SupportShortcutAction) -> String {
    switch action {
    case .previousChat:
        return "Previous Chat in List"
    case .nextChat:
        return "Next Chat in List"
    case .previousOpenedChat:
        return "Previous Opened Chat"
    case .nextOpenedChat:
        return "Next Opened Chat"
    case .muteChat:
        return "Mute or Unmute Chat"
    case .sendAndStay:
        return "Send and Stay"
    case .closeChat:
        return "Close Chat"
    case .reloadTemplates:
        return "Reload Templates"
    case .showCurrentChat:
        return "Show Current Chat in List"
    case .openAbuseBot:
        return "Open Abuse Bot"
    }
}

public func supportKeyShortcuts(combos: [SupportKeyCombo], title: String?, wantsPriorityOverText: Bool = false, perform: @escaping () -> Void) -> [KeyShortcut] {
    return combos.enumerated().map { index, combo in
        return KeyShortcut(title: index == 0 ? (title ?? "") : "", input: supportKeyCommandInput(combo.key), modifiers: supportKeyCommandModifiers(combo.modifiers), wantsPriorityOverText: wantsPriorityOverText, action: perform)
    }
}

private func supportKeyCommandInput(_ key: String) -> String {
    switch key {
    case SupportKeyCombo.escapeKey:
        return UIKeyCommand.inputEscape
    case SupportKeyCombo.upKey:
        return UIKeyCommand.inputUpArrow
    case SupportKeyCombo.downKey:
        return UIKeyCommand.inputDownArrow
    case "Left":
        return UIKeyCommand.inputLeftArrow
    case "Right":
        return UIKeyCommand.inputRightArrow
    default:
        if key.hasPrefix("F"), Int(key.dropFirst()) != nil {
            return "UIKeyInput\(key)"
        }
        return key
    }
}

private func supportKeyCommandModifiers(_ modifiers: SupportKeyCombo.Modifiers) -> UIKeyModifierFlags {
    var result: UIKeyModifierFlags = []
    if modifiers.contains(.shift) {
        result.insert(.shift)
    }
    if modifiers.contains(.control) {
        result.insert(.control)
    }
    if modifiers.contains(.alternate) {
        result.insert(.alternate)
    }
    if modifiers.contains(.command) {
        result.insert(.command)
    }
    return result
}
