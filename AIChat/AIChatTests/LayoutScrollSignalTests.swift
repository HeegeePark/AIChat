@testable import AIChat
import Foundation
import Testing

@MainActor
struct LayoutScrollSignalTests {
    @Test func `signal before wait completes immediately without waiting for fallback`() async {
        let signal = LayoutScrollSignal()
        let id = UUID()
        signal.begin(id: id)
        signal.signalAppear(id: id)

        let started = ContinuousClock.now
        // 폴백이 길어도 readyID 경로면 즉시 반환해야 한다 — 지우면 1초 이상 걸린다.
        await signal.wait(for: id, fallbackTimeout: .seconds(1))
        let elapsed = ContinuousClock.now - started
        #expect(elapsed < .milliseconds(200))
    }

    @Test func `wait then signal unblocks without relying on fallback`() async {
        let signal = LayoutScrollSignal()
        let id = UUID()
        signal.begin(id: id)

        let waiter = Task { @MainActor in
            await signal.wait(for: id, fallbackTimeout: .seconds(2))
        }
        // wait가 continuation을 걸 시간을 짧게 준다.
        try? await Task.sleep(for: .milliseconds(20))
        signal.signalAppear(id: id)

        let started = ContinuousClock.now
        await waiter.value
        let elapsed = ContinuousClock.now - started
        #expect(elapsed < .milliseconds(500))
    }

    @Test func `cancelWait unblocks a hanging wait`() async {
        let signal = LayoutScrollSignal()
        let id = UUID()
        signal.begin(id: id)

        let waiter = Task { @MainActor in
            await signal.wait(for: id, fallbackTimeout: .seconds(5))
        }
        try? await Task.sleep(for: .milliseconds(20))
        signal.cancelWait()

        let started = ContinuousClock.now
        await waiter.value
        let elapsed = ContinuousClock.now - started
        #expect(elapsed < .milliseconds(500))
    }

    @Test func `wrong id signal does not complete wait before fallback`() async {
        let signal = LayoutScrollSignal()
        let pending = UUID()
        let other = UUID()
        signal.begin(id: pending)

        let waiter = Task { @MainActor in
            await signal.wait(for: pending, fallbackTimeout: .milliseconds(80))
        }
        try? await Task.sleep(for: .milliseconds(10))
        signal.signalAppear(id: other)

        let started = ContinuousClock.now
        await waiter.value
        let elapsed = ContinuousClock.now - started
        // 잘못된 id 신호는 무시 → 폴백(~80ms)까지 기다려야 끝난다.
        #expect(elapsed >= .milliseconds(40))
    }

    @Test func `fallback alone completes wait when no signal arrives`() async {
        let signal = LayoutScrollSignal()
        let id = UUID()
        signal.begin(id: id)

        let started = ContinuousClock.now
        await signal.wait(for: id, fallbackTimeout: .milliseconds(50))
        let elapsed = ContinuousClock.now - started
        #expect(elapsed >= .milliseconds(30))
        #expect(elapsed < .milliseconds(500))
    }
}
