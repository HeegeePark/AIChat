import UIKit
import XCTest

/// 생성 중 입력 액션이 중지로 바뀌고, 탭하면 다시 전송 가능한 상태로 돌아오는 화면 흐름.
@MainActor
final class StopGenerationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testStopButtonCancelsGenerationAndRestoresSendButton() {
        let app = XCUIApplication()
        UITestSupport.launchApp(app, arguments: [UITestSupport.uiTestingArgument])

        let messageInput = UITestSupport.messageInput(in: app)
        let sendButton = app.buttons["sendButton"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5), "sendButton should appear")

        messageInput.tap()
        UIPasteboard.general.string = "QA:slow QA:long stop-flow"
        messageInput.typeKey("v", modifierFlags: .command)
        XCTAssertTrue(sendButton.isEnabled, "send should enable after typing")
        sendButton.tap()

        let stopButton = app.buttons["stopButton"]
        XCTAssertTrue(
            stopButton.waitForExistence(timeout: 5),
            "stopButton should replace sendButton while generating",
        )
        stopButton.tap()

        XCTAssertTrue(
            UITestSupport.waitUntilGone(stopButton),
            "stopButton should disappear after cancellation settles",
        )
        XCTAssertTrue(
            sendButton.waitForExistence(timeout: 5),
            "sendButton should return after cancellation",
        )
        XCTAssertFalse(sendButton.isEnabled, "send should wait for a new message")
    }
}
