import XCTest

/// timeout 실패 표시 → 재시도 → 고정 성공 응답 회귀. 실제 idle 시간은 기다리지 않는다.
@MainActor
final class TimeoutRetryUITests: XCTestCase {
    private let failureCopy = "응답을 받지 못했어요"
    private let successCopy = "UITest-TimeoutRetry-OK"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTimeoutShowsRetryThenRecovers() {
        let app = XCUIApplication()
        UITestSupport.launchApp(
            app,
            arguments: [
                UITestSupport.uiTestingArgument,
                UITestSupport.timeoutOnceArgument,
            ],
        )

        let unique = sendUniqueMessage(in: app)
        assertFailureAndRetry(in: app)
        assertRecovered(in: app, uniqueUserMessage: unique)
    }

    private func sendUniqueMessage(in app: XCUIApplication) -> String {
        let messageInput = UITestSupport.messageInput(in: app)
        let sendButton = app.buttons["sendButton"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5), "sendButton should appear")

        let unique = "UITimeout-\(UUID().uuidString)"
        messageInput.tap()
        messageInput.typeText(unique)
        XCTAssertTrue(sendButton.isEnabled, "send should enable after typing")
        sendButton.tap()

        let userBubble = UITestSupport.staticText(matching: unique, in: app)
        XCTAssertTrue(userBubble.waitForExistence(timeout: 5), "user message should appear")
        return unique
    }

    private func assertFailureAndRetry(in app: XCUIApplication) {
        let failureText = UITestSupport.staticText(matching: failureCopy, in: app)
        XCTAssertTrue(failureText.waitForExistence(timeout: 5), "timeout empty-failure copy should appear")

        let retryButton = app.buttons["retryButton"]
        XCTAssertTrue(retryButton.waitForExistence(timeout: 5), "retryButton should appear")
        retryButton.tap()

        XCTAssertTrue(UITestSupport.waitUntilGone(retryButton, timeout: 5), "retryButton should disappear after retry")
        XCTAssertTrue(UITestSupport.waitUntilGone(failureText, timeout: 5), "failure copy should disappear after retry")
    }

    private func assertRecovered(in app: XCUIApplication, uniqueUserMessage: String) {
        let successText = UITestSupport.staticText(matching: successCopy, in: app)
        XCTAssertTrue(
            successText.waitForExistence(timeout: 5),
            "deterministic success text should appear after retry",
        )

        let userMatches = app.staticTexts.matching(NSPredicate(format: "label == %@", uniqueUserMessage))
        XCTAssertEqual(userMatches.count, 1, "retry must not duplicate the user message")
    }
}
