import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramPresentationData

final class ChatListLoadMoreItem: ListViewItem {
    var neighborDescriptor: AnyEquatable {
        return AnyEquatable.noNeighborInfluence
    }

    let theme: PresentationTheme
    let isLoading: Bool
    let showsFolderLimit: Bool
    let action: () -> Void

    var selectable: Bool {
        return !self.isLoading
    }

    init(theme: PresentationTheme, isLoading: Bool, showsFolderLimit: Bool, action: @escaping () -> Void) {
        self.theme = theme
        self.isLoading = isLoading
        self.showsFolderLimit = showsFolderLimit
        self.action = action
    }

    func selected(listView: ListView) {
        listView.clearHighlightAnimated(true)
        self.action()
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = ChatListLoadMoreItemNode()
            let (layout, apply) = node.asyncLayout()(self, params)

            node.contentSize = layout.contentSize
            node.insets = layout.insets

            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in apply() })
                })
            }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, neighbors: ListViewItemNeighbors, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            assert(node() is ChatListLoadMoreItemNode)
            if let nodeValue = node() as? ChatListLoadMoreItemNode {
                let layout = nodeValue.asyncLayout()
                async {
                    let (nodeLayout, apply) = layout(self, params)
                    Queue.mainQueue().async {
                        completion(nodeLayout, { _ in
                            apply()
                        })
                    }
                }
            }
        }
    }
}

final class ChatListLoadMoreItemNode: ListViewItemNode {
    private let highlightedBackgroundNode: ASDisplayNode
    private let titleNode: TextNode
    private let captionNode: TextNode

    private var item: ChatListLoadMoreItem?

    required init() {
        self.highlightedBackgroundNode = ASDisplayNode()
        self.highlightedBackgroundNode.isLayerBacked = true
        self.highlightedBackgroundNode.alpha = 0.0

        self.titleNode = TextNode()
        self.titleNode.isUserInteractionEnabled = false

        self.captionNode = TextNode()
        self.captionNode.isUserInteractionEnabled = false

        super.init(layerBacked: false)

        self.addSubnode(self.highlightedBackgroundNode)
        self.addSubnode(self.titleNode)
        self.addSubnode(self.captionNode)
    }

    override func layoutForParams(_ params: ListViewItemLayoutParams, item: ListViewItem, neighbors: ListViewItemNeighbors) {
        let layout = self.asyncLayout()
        let (_, apply) = layout(item as! ChatListLoadMoreItem, params)
        apply()
    }

    override func setHighlighted(_ highlighted: Bool, at point: CGPoint, animated: Bool) {
        super.setHighlighted(highlighted, at: point, animated: animated)

        let alpha: CGFloat = highlighted ? 1.0 : 0.0
        if !highlighted && animated {
            self.highlightedBackgroundNode.layer.animateAlpha(from: self.highlightedBackgroundNode.alpha, to: alpha, duration: 0.4)
        }
        self.highlightedBackgroundNode.alpha = alpha
    }

    func asyncLayout() -> (_ item: ChatListLoadMoreItem, _ params: ListViewItemLayoutParams) -> (ListViewItemNodeLayout, () -> Void) {
        let makeTitleLayout = TextNode.asyncLayout(self.titleNode)
        let makeCaptionLayout = TextNode.asyncLayout(self.captionNode)

        return { [weak self] item, params in
            let sideInset: CGFloat = 16.0
            let verticalInset: CGFloat = 12.0
            let captionSpacing: CGFloat = 4.0
            let constrainedSize = CGSize(width: max(1.0, params.width - params.leftInset - params.rightInset - sideInset * 2.0), height: .greatestFiniteMagnitude)

            let title = item.isLoading ? "Loading..." : "Load more"
            let titleColor = item.isLoading ? item.theme.list.itemSecondaryTextColor : item.theme.list.itemAccentColor
            let titleLayout = makeTitleLayout(TextNodeLayoutArguments(
                attributedString: NSAttributedString(string: title, font: Font.regular(17.0), textColor: titleColor),
                maximumNumberOfLines: 1,
                truncationType: .end,
                constrainedSize: constrainedSize,
                alignment: .center
            ))

            let captionString: NSAttributedString? = item.showsFolderLimit ? NSAttributedString(string: "Older chats are not loaded, so this folder may be missing some.", font: Font.regular(13.0), textColor: item.theme.list.itemSecondaryTextColor) : nil
            let captionLayout = makeCaptionLayout(TextNodeLayoutArguments(
                attributedString: captionString,
                maximumNumberOfLines: 0,
                truncationType: .end,
                constrainedSize: constrainedSize,
                alignment: .center
            ))

            var contentHeight = verticalInset + titleLayout.0.size.height
            if item.showsFolderLimit {
                contentHeight += captionSpacing + captionLayout.0.size.height
            }
            contentHeight += verticalInset

            let layout = ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: contentHeight), insets: UIEdgeInsets())

            return (layout, { [weak self] in
                guard let self else {
                    return
                }

                self.item = item
                self.contentSize = layout.contentSize
                self.insets = layout.insets

                let _ = titleLayout.1()
                let _ = captionLayout.1()

                let bandWidth = params.width - params.leftInset - params.rightInset
                self.titleNode.frame = CGRect(origin: CGPoint(x: params.leftInset + floor((bandWidth - titleLayout.0.size.width) * 0.5), y: verticalInset), size: titleLayout.0.size)
                self.captionNode.frame = CGRect(origin: CGPoint(x: params.leftInset + floor((bandWidth - captionLayout.0.size.width) * 0.5), y: verticalInset + titleLayout.0.size.height + captionSpacing), size: captionLayout.0.size)

                self.highlightedBackgroundNode.backgroundColor = item.theme.chatList.itemHighlightedBackgroundColor
                self.highlightedBackgroundNode.frame = CGRect(origin: CGPoint(), size: layout.contentSize)
            })
        }
    }
}
