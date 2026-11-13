import XCTest

/// 접힌 말풍선 “더 보기 → 펼침” 회귀. AI 응답 완료를 전제로 두지 않는다.
@MainActor
final class ExpandUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMoreButtonExpandsCollapsedUserMessage() {
        let app = XCUIApplication()
        UITestSupport.launchApp(app, arguments: [UITestSupport.uiTestingArgument])

        let messageInput = UITestSupport.messageInput(in: app)
        let sendButton = app.buttons["sendButton"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5), "sendButton should appear")

        // 5줄 초과(≥6 개행 줄)로 폭과 무관하게 접힘. 고유 토큰은 마지막 줄 — 접힌 상태에서는 잘린다.
        let token = "UIExpand-\(UUID().uuidString)"
        let longMessage = [
            "expand-line-1",
            "expand-line-2",
            "expand-line-3",
            "expand-line-4",
            "expand-line-5",
            token,
        ].joined(separator: "\n")

        messageInput.tap()
        messageInput.typeText(longMessage)
        XCTAssertTrue(sendButton.isEnabled, "send should enable after typing")
        sendButton.tap()

        // 장문 에코로 사용자·AI 말풍선 모두 접히면 moreButton이 둘 이상일 수 있다.
        // 단일 원소 쿼리 탭은 ambiguous match로 실패하므로 matching + firstMatch만 쓴다.
        let moreButtons = app.buttons.matching(identifier: "moreButton")
        XCTAssertTrue(
            moreButtons.firstMatch.waitForExistence(timeout: 5),
            "moreButton should appear on a collapsed long message",
        )

        var guardCount = 0
        while moreButtons.count > 0, guardCount < 4 {
            moreButtons.firstMatch.tap()
            guardCount += 1
        }
        XCTAssertEqual(
            moreButtons.count,
            0,
            "all moreButtons should be gone after expand",
        )

        // 펼친 말풍선은 줄 단위가 아니라 원문 전체 UILabel 하나 — 라벨이 토큰만이 아니다.
        // 접힌 동안은 분할·말줄임이라 전체 원문이 트리에 없고, 펼친 뒤에야 나타난다.
        let expandedBody = UITestSupport.staticText(matching: longMessage, in: app)
        XCTAssertTrue(
            expandedBody.waitForExistence(timeout: 5),
            "full long message (with last-line token) should appear after expand",
        )
    }
}
