import XCTest

/// 채팅 화면 전송 경로 스모크: 입력 → 전송 활성 → 전송 후 입력 비움·사용자 말풍선 노출.
/// AI 응답·완료 상태는 기다리지 않는다.
@MainActor
final class SendSmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSendClearsInputAndShowsUserMessage() {
        let app = XCUIApplication()
        // 저장 대화·펼침 영속과 교차 오염을 막기 위해 UI 테스트 전용 빈 store 경로를 쓴다.
        UITestSupport.launchApp(app, arguments: [UITestSupport.uiTestingArgument])

        let messageInputElement = UITestSupport.messageInput(in: app)

        let sendButton = app.buttons["sendButton"]
        XCTAssertTrue(
            sendButton.waitForExistence(timeout: 5),
            "sendButton should appear on the chat screen",
        )

        XCTAssertFalse(sendButton.isEnabled, "send should be disabled when input is empty")

        let unique = "UISmoke-\(UUID().uuidString)"
        messageInputElement.tap()
        messageInputElement.typeText(unique)

        XCTAssertTrue(sendButton.isEnabled, "send should enable after typing a non-empty message")

        sendButton.tap()

        let clearedValue = (messageInputElement.value as? String) ?? ""
        let placeholder = messageInputElement.placeholderValue ?? ""
        XCTAssertTrue(
            clearedValue.isEmpty || clearedValue == placeholder,
            "input should clear after send (value: \(clearedValue))",
        )

        let userMessage = UITestSupport.staticText(matching: unique, in: app)
        XCTAssertTrue(
            userMessage.waitForExistence(timeout: 5),
            "sent unique message should appear in the accessibility tree",
        )
    }
}
