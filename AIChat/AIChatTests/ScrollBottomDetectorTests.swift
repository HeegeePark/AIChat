@testable import AIChat
import CoreGraphics
import Testing

struct ScrollBottomDetectorTests {
    // MARK: - Offset API

    @Test func `scrolled up with large distance is not at bottom`() {
        // content 2000, viewport 800, offset 0 → distance = 2000 - 800 = 1200
        #expect(!ScrollBottomDetector.isAtBottom(
            contentOffsetY: 0,
            contentHeight: 2000,
            viewportHeight: 800,
        ))
    }

    @Test func `near bottom within tolerance is at bottom`() {
        // distance = 2000 - (1185 + 800) = 15 <= 20
        #expect(ScrollBottomDetector.isAtBottom(
            contentOffsetY: 1185,
            contentHeight: 2000,
            viewportHeight: 800,
        ))
    }

    @Test func `distance exactly zero is at bottom`() {
        // distance = 2000 - (1200 + 800) = 0
        #expect(ScrollBottomDetector.isAtBottom(
            contentOffsetY: 1200,
            contentHeight: 2000,
            viewportHeight: 800,
        ))
    }

    @Test func `distance equal to tolerance is at bottom`() {
        // distance = 2000 - (1180 + 800) = 20
        #expect(ScrollBottomDetector.isAtBottom(
            contentOffsetY: 1180,
            contentHeight: 2000,
            viewportHeight: 800,
            tolerance: 20,
        ))
    }

    @Test func `distance one past tolerance is not at bottom`() {
        // distance = 2000 - (1179 + 800) = 21
        #expect(!ScrollBottomDetector.isAtBottom(
            contentOffsetY: 1179,
            contentHeight: 2000,
            viewportHeight: 800,
            tolerance: 20,
        ))
    }

    @Test func `zero tolerance allows exact bottom only`() {
        #expect(ScrollBottomDetector.isAtBottom(
            contentOffsetY: 1200,
            contentHeight: 2000,
            viewportHeight: 800,
            tolerance: 0,
        ))
        #expect(!ScrollBottomDetector.isAtBottom(
            contentOffsetY: 1199,
            contentHeight: 2000,
            viewportHeight: 800,
            tolerance: 0,
        ))
    }

    @Test func `short list contentHeight less than or equal to viewport is at bottom`() {
        #expect(ScrollBottomDetector.isAtBottom(
            contentOffsetY: 0,
            contentHeight: 400,
            viewportHeight: 800,
        ))
        #expect(ScrollBottomDetector.isAtBottom(
            contentOffsetY: 0,
            contentHeight: 800,
            viewportHeight: 800,
        ))
    }

    @Test func `adjustedContentInsetBottom does not falsely mark mid scroll as bottom`() {
        // Mid-list: distance = 2000 - (1000 + 800) + 0 = 200 → not at bottom
        #expect(!ScrollBottomDetector.isAtBottom(
            contentOffsetY: 1000,
            contentHeight: 2000,
            viewportHeight: 800,
            adjustedContentInsetBottom: 0,
        ))
        // Same offset with large inset must stay not-at-bottom (wrong sign would claim bottom).
        // distance = 2000 - 1800 + 190 = 390
        #expect(!ScrollBottomDetector.isAtBottom(
            contentOffsetY: 1000,
            contentHeight: 2000,
            viewportHeight: 800,
            adjustedContentInsetBottom: 190,
        ))
    }

    @Test func `adjustedContentInsetBottom at true UIKit bottom is at bottom`() {
        // maxOffset ≈ contentHeight - viewport + inset = 2000 - 800 + 100 = 1300
        // distance = 2000 - (1300 + 800) + 100 = 0
        #expect(ScrollBottomDetector.isAtBottom(
            contentOffsetY: 1300,
            contentHeight: 2000,
            viewportHeight: 800,
            adjustedContentInsetBottom: 100,
        ))
        // Slightly above true bottom
        #expect(!ScrollBottomDetector.isAtBottom(
            contentOffsetY: 1200,
            contentHeight: 2000,
            viewportHeight: 800,
            adjustedContentInsetBottom: 100,
            tolerance: 0,
        ))
    }

    @Test func `invalid geometry height zero is at bottom`() {
        #expect(ScrollBottomDetector.isAtBottom(
            contentOffsetY: 0,
            contentHeight: 0,
            viewportHeight: 800,
        ))
        #expect(ScrollBottomDetector.isAtBottom(
            contentOffsetY: 0,
            contentHeight: 2000,
            viewportHeight: 0,
        ))
        #expect(ScrollBottomDetector.isAtBottom(
            contentOffsetY: 0,
            contentHeight: 0,
            viewportHeight: 0,
        ))
    }

    @Test func `trailingSlack treats message end as bottom not content spacer end`() {
        // messages 1200 + spacer 800 = content 2000, viewport 800.
        // scrollTo(lastMessage, .bottom) leaves ~full spacer below → raw distance ≈ 800.
        // Without slack: not at bottom. With slack 800: distance 0 → at bottom.
        #expect(!ScrollBottomDetector.isAtBottom(
            contentOffsetY: 400,
            contentHeight: 2000,
            viewportHeight: 800,
            trailingSlack: 0,
        ))
        #expect(ScrollBottomDetector.isAtBottom(
            contentOffsetY: 400,
            contentHeight: 2000,
            viewportHeight: 800,
            trailingSlack: 800,
        ))
        // Scrolled up further so message end is above viewport → still not at bottom with slack.
        #expect(!ScrollBottomDetector.isAtBottom(
            contentOffsetY: 0,
            contentHeight: 2000,
            viewportHeight: 800,
            trailingSlack: 800,
        ))
    }
}
