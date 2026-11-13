import XCTest

/// UI 테스트 공통: launch args, 입력 필드 해석, 원문 라벨 조회, 존재 폴링.
enum UITestSupport {
    static let uiTestingArgument = "-ui-testing"
    static let timeoutOnceArgument = "-ui-testing-timeout-once"

    @MainActor
    static func launchApp(_ app: XCUIApplication, arguments: [String]) {
        app.launchArguments = arguments
        app.launch()
    }

    /// `TextField(axis: .vertical)`은 textView로 잡히는 경우가 있다.
    @MainActor
    static func messageInput(in app: XCUIApplication, timeout: TimeInterval = 5) -> XCUIElement {
        let field = app.textFields["messageInput"]
        if field.waitForExistence(timeout: timeout) {
            return field
        }
        let view = app.textViews["messageInput"]
        XCTAssertTrue(view.waitForExistence(timeout: timeout), "messageInput should appear")
        return view
    }

    /// 말풍선은 원문 라벨을 노출한다 (UILabel char wrapping — ZWSP 없음).
    /// 접근성 트리가 개행을 공백으로 정규화하는 경우도 허용한다.
    @MainActor
    static func staticText(matching text: String, in app: XCUIApplication) -> XCUIElement {
        let normalized = text.replacingOccurrences(of: "\n", with: " ")
        if text == normalized {
            return app.staticTexts[text]
        }
        return app.staticTexts.matching(
            NSPredicate(format: "label == %@ OR label == %@", text, normalized),
        ).firstMatch
    }

    /// `exists == false`가 될 때까지 폴링 (고정 sleep 없음).
    @MainActor
    static func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
