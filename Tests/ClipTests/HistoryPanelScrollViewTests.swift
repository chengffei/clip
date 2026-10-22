import AppKit
import XCTest
@testable import capcap

@MainActor
final class HistoryPanelScrollViewTests: XCTestCase {
    func testCardsRemainFullyVisibleWithOverlayScrollers() {
        assertCardsRemainFullyVisible(styles: [.overlay])
    }

    func testCardsRemainFullyVisibleWithLegacyScrollers() {
        assertCardsRemainFullyVisible(styles: [.legacy])
    }

    func testCardsRemainFullyVisibleWhenScrollerStyleChanges() {
        assertCardsRemainFullyVisible(styles: [.overlay, .legacy, .overlay])
    }

    private func assertCardsRemainFullyVisible(
        styles: [NSScroller.Style], file: StaticString = #filePath, line: UInt = #line
    ) {
        _ = NSApplication.shared
        let tileHeight: CGFloat = 134
        let frame = NSRect(x: 0, y: 0, width: 1000, height: tileHeight)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        let scrollView = HistoryPanelScrollView(frame: frame)
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = styles[0]
        let collectionView = NSCollectionView(frame: NSRect(x: 0, y: 0, width: 1, height: tileHeight))
        let layout = NSCollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = NSSize(width: 150, height: tileHeight)
        collectionView.collectionViewLayout = layout
        let dataSource = CardDataSource()
        collectionView.dataSource = dataSource
        collectionView.register(NSCollectionViewItem.self, forItemWithIdentifier: CardDataSource.identifier)
        scrollView.documentView = collectionView
        window.contentView = scrollView

        for style in styles {
            scrollView.scrollerStyle = style
            collectionView.reloadData()
            window.contentView?.layoutSubtreeIfNeeded()
            scrollView.tile()
            collectionView.layoutSubtreeIfNeeded()

            XCTAssertFalse(scrollView.hasHorizontalScroller, file: file, line: line)
            XCTAssertEqual(scrollView.contentSize.height, tileHeight, accuracy: 0.01, file: file, line: line)
            let card = layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))
            XCTAssertNotNil(card, file: file, line: line)
            if let card {
                let viewport = scrollView.documentVisibleRect
                XCTAssertGreaterThanOrEqual(card.frame.minY, viewport.minY, file: file, line: line)
                XCTAssertLessThanOrEqual(card.frame.maxY, viewport.maxY, file: file, line: line)
            }
        }
        withExtendedLifetime(dataSource) {}
    }
}

@MainActor
private final class CardDataSource: NSObject, NSCollectionViewDataSource {
    static let identifier = NSUserInterfaceItemIdentifier("HistoryScrollTestCard")

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { 10 }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        collectionView.makeItem(withIdentifier: Self.identifier, for: indexPath)
    }
}
