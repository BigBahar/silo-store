//
//  SiloMenuAdapter.swift
//  Silo Store
//
//  Lets existing UIKit menus (built from UIAction and UIMenu) open in Silo's list
//  instead of the system menu. Actions made with `UIAction.silo(...)` remember
//  their handler so the list can run it; nested menus flatten into headed groups.
//

import ObjectiveC
import UIKit

private final class SiloActionHandlerBox
{
    let handler: UIActionHandler

    init(_ handler: @escaping UIActionHandler)
    {
        self.handler = handler
    }
}

private nonisolated(unsafe) var siloHandlerKey: UInt8 = 0

extension UIAction
{
    /// Same as `UIAction(title:image:attributes:handler:)`, but the handler can be run from a Silo list.
    static func silo(title: String, image: UIImage? = nil, attributes: UIMenuElement.Attributes = [], handler: @escaping UIActionHandler) -> UIAction
    {
        let action = UIAction(title: title, image: image, attributes: attributes) { action in
            handler(action)
        }
        objc_setAssociatedObject(action, &siloHandlerKey, SiloActionHandlerBox(handler), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return action
    }

    fileprivate var siloHandler: UIActionHandler? {
        return (objc_getAssociatedObject(self, &siloHandlerKey) as? SiloActionHandlerBox)?.handler
    }
}

enum SiloMenuAdapter
{
    static func items(from menu: UIMenu) -> [SiloListItem]
    {
        var items = [SiloListItem]()
        for element in menu.children
        {
            self.append(element, to: &items)
        }
        return items
    }

    private static func append(_ element: UIMenuElement, to items: inout [SiloListItem])
    {
        if let action = element as? UIAction
        {
            guard let handler = action.siloHandler else { return }

            items.append(SiloListItem(
                title: action.title,
                isSelected: action.state == .on,
                isDestructive: action.attributes.contains(.destructive),
                isEnabled: !action.attributes.contains(.disabled),
                action: { handler(action) }
            ))
        }
        else if let submenu = element as? UIMenu
        {
            if !submenu.options.contains(.displayInline), !submenu.title.isEmpty
            {
                items.append(SiloListItem(title: submenu.title, isHeader: true, action: {}))
            }

            for child in submenu.children
            {
                self.append(child, to: &items)
            }
        }
    }
}
