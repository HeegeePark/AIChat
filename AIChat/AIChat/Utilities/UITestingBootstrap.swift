import Foundation

/// XCUITest launch argument → store·service·ViewModel 조립.
/// 분기를 App 진입점에만 모아 프로덕션 기본 경로를 흩뜨리지 않는다.
enum UITestingBootstrap {
    static let uiTestingArgument = "-ui-testing"
    static let timeoutOnceArgument = "-ui-testing-timeout-once"
    private static let suiteName = "AIChat.UITesting"

    /// 인자 없으면 기본 `ChatViewModel()`(표준 store + `MockChatService` 기본값).
    /// `-ui-testing`: 전용 suite를 비운 빈 store + 빠른 성공 Mock + `characterDelay` 0.
    /// 여기에 `-ui-testing-timeout-once`: 첫 send만 timeout, 이후 고정 성공.
    @MainActor
    static func makeViewModel(
        arguments: [String] = ProcessInfo.processInfo.arguments,
    ) -> ChatViewModel {
        guard arguments.contains(uiTestingArgument) else {
            return ChatViewModel()
        }

        let store = makeEmptyUITestingStore()
        let service: any ChatService = if arguments.contains(timeoutOnceArgument) {
            UITestingTimeoutOnceChatService()
        } else {
            MockChatService(delay: .zero, chunkDelay: .zero, includesPrefix: { false })
        }

        return ChatViewModel(
            service: service,
            store: store,
            characterDelay: .zero,
            debounceInterval: .zero,
        )
    }

    /// 표준 `UserDefaults`는 건드리지 않고, UI 테스트 전용 suite만 비운다.
    private static func makeEmptyUITestingStore() -> ChatHistoryStore {
        UserDefaults().removePersistentDomain(forName: suiteName)
        let defaults = UserDefaults(suiteName: suiteName) ?? UserDefaults()
        return ChatHistoryStore(defaults: defaults)
    }
}
