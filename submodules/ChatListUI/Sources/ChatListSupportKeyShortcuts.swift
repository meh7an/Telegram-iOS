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

public func supportTemplatesReloadKeyShortcuts(context: AccountContext, present: @escaping (ViewController) -> Void) -> [KeyShortcut] {
    guard let supportContext = context.supportContext, let manager = context.supportTemplates else {
        return []
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
    return [
        KeyShortcut(title: "Reload Templates", input: UIKeyCommand.f5, action: reload),
        KeyShortcut(input: "R", modifiers: [.control, .shift], action: reload),
        KeyShortcut(input: "R", modifiers: [.command, .shift], action: reload)
    ]
}
