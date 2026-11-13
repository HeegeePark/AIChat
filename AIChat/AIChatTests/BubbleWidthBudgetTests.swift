@testable import AIChat
import CoreGraphics
import Testing

struct BubbleWidthBudgetTests {
    private let containerWidth: CGFloat = 390
    private let padding: CGFloat = 32
    private let avatarColumn: CGFloat = 36
    private let ratio: CGFloat = 0.75

    @Test func `user max is content width times ratio`() {
        let user = BubbleWidthBudget.maxBubbleWidth(
            for: .user,
            containerWidth: containerWidth,
            stackHorizontalPadding: padding,
            avatarColumn: avatarColumn,
            ratio: ratio,
        )
        #expect(user == (containerWidth - padding) * ratio)
    }

    @Test func `ai max subtracts avatar column before ratio`() {
        let ai = BubbleWidthBudget.maxBubbleWidth(
            for: .ai,
            containerWidth: containerWidth,
            stackHorizontalPadding: padding,
            avatarColumn: avatarColumn,
            ratio: ratio,
        )
        #expect(ai == (containerWidth - padding - avatarColumn) * ratio)
    }

    @Test func `user max is greater than or equal to ai max for same inputs`() {
        let user = BubbleWidthBudget.maxBubbleWidth(
            for: .user,
            containerWidth: containerWidth,
            stackHorizontalPadding: padding,
            avatarColumn: avatarColumn,
            ratio: ratio,
        )
        let ai = BubbleWidthBudget.maxBubbleWidth(
            for: .ai,
            containerWidth: containerWidth,
            stackHorizontalPadding: padding,
            avatarColumn: avatarColumn,
            ratio: ratio,
        )
        #expect(user > ai)
        #expect(user - ai == avatarColumn * ratio)
    }

    @Test func `zero or negative container width returns zero`() {
        #expect(
            BubbleWidthBudget.maxBubbleWidth(
                for: .user,
                containerWidth: 0,
                stackHorizontalPadding: padding,
                avatarColumn: avatarColumn,
                ratio: ratio,
            ) == 0,
        )
        #expect(
            BubbleWidthBudget.maxBubbleWidth(
                for: .ai,
                containerWidth: -10,
                stackHorizontalPadding: padding,
                avatarColumn: avatarColumn,
                ratio: ratio,
            ) == 0,
        )
    }

    @Test func `padding that exhausts content width returns zero`() {
        #expect(
            BubbleWidthBudget.maxBubbleWidth(
                for: .user,
                containerWidth: 30,
                stackHorizontalPadding: 32,
                avatarColumn: avatarColumn,
                ratio: ratio,
            ) == 0,
        )
    }

    @Test func `avatar column that exhausts ai budget returns zero`() {
        // contentWidth 20, avatar 36 → ai available ≤ 0
        #expect(
            BubbleWidthBudget.maxBubbleWidth(
                for: .ai,
                containerWidth: 52,
                stackHorizontalPadding: 32,
                avatarColumn: 36,
                ratio: ratio,
            ) == 0,
        )
        #expect(
            BubbleWidthBudget.maxBubbleWidth(
                for: .user,
                containerWidth: 52,
                stackHorizontalPadding: 32,
                avatarColumn: 36,
                ratio: ratio,
            ) == 20 * ratio,
        )
    }

    @Test func `non positive ratio returns zero`() {
        #expect(
            BubbleWidthBudget.maxBubbleWidth(
                for: .user,
                containerWidth: containerWidth,
                stackHorizontalPadding: padding,
                avatarColumn: avatarColumn,
                ratio: 0,
            ) == 0,
        )
    }
}
