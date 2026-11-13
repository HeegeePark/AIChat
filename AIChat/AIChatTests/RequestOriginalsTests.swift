@testable import AIChat
import Foundation
import Testing

/// in-flight 맵 수명의 순수 로직. ViewModel 경유 없이 claim/rekey/취소/정리 outcome을 고정한다.
struct RequestOriginalsTests {
    @Test func `recordBatch reuses single anchor while updating batch contents`() throws {
        var originals = RequestOriginals()
        originals.recordBatch(["A"])
        let firstAnchor = try #require(originals.batchAnchor)
        #expect(originals.map[firstAnchor] == .batch(["A"]))

        originals.recordBatch(["A", "B"])
        #expect(originals.batchAnchor == firstAnchor)
        #expect(originals.map.count == 1)
        #expect(originals.map[firstAnchor] == .batch(["A", "B"]))
    }

    @Test func `clearPendingBatch preserves failures and next batch gets an independent anchor`() throws {
        var originals = RequestOriginals()
        let failedBubble = UUID()
        originals.map[failedBubble] = .batch(["A"])
        originals.recordBatch(["A"])
        let stoppedAnchor = try #require(originals.batchAnchor)

        originals.clearPendingBatch()
        originals.recordBatch(["B"])
        let nextAnchor = try #require(originals.batchAnchor)

        #expect(nextAnchor != stoppedAnchor)
        #expect(originals.map[stoppedAnchor] == nil)
        #expect(originals.map[failedBubble] == .batch(["A"]))
        #expect(originals.map[nextAnchor] == .batch(["B"]))
        #expect(originals.map.count == 2)
    }

    @Test func `claimRunKey hands batch anchor once then rekey moves to bubble id`() throws {
        var originals = RequestOriginals()
        originals.recordBatch(["A"])
        let claimed = originals.claimRunKey(for: .batch(["A"]))
        let anchor = try #require(claimed)
        #expect(originals.batchAnchor == nil)
        #expect(originals.claimRunKey(for: .batch(["A"])) == nil)

        let bubble = UUID()
        originals.rekey(from: anchor, to: bubble, request: .batch(["A"]))
        #expect(originals.map[anchor] == nil)
        #expect(originals.map[bubble] == .batch(["A"]))
    }

    @Test func `claimRunKey for greeting is always nil`() {
        var originals = RequestOriginals()
        #expect(originals.claimRunKey(for: .greeting) == nil)
    }

    @Test func `rekey without old key still installs request under new id`() {
        var originals = RequestOriginals()
        let bubble = UUID()
        originals.rekey(from: nil, to: bubble, request: .greeting)
        #expect(originals.map[bubble] == .greeting)
    }

    @Test func `recordFailure keeps retryable and drops non-retryable`() {
        var originals = RequestOriginals()
        let retryableID = UUID()
        let nonRetryableID = UUID()
        originals.map[retryableID] = .batch(["A"])
        originals.map[nonRetryableID] = .batch(["B"])

        originals.recordFailure(.network, id: retryableID, request: .batch(["A"]))
        originals.recordFailure(.decoding, id: nonRetryableID, request: .batch(["B"]))

        #expect(originals.map[retryableID] == .batch(["A"]))
        #expect(originals.map[nonRetryableID] == nil)
    }

    @Test func `recordCancellation removes bubble key without touching newer batch anchor`() throws {
        var originals = RequestOriginals()
        let cancelledBubble = UUID()
        originals.map[cancelledBubble] = .batch(["A"])
        originals.recordBatch(["A", "B"])
        let newAnchor = try #require(originals.batchAnchor)

        let next = originals.recordCancellation(id: cancelledBubble, runKey: cancelledBubble)
        #expect(next == nil)
        #expect(originals.map[cancelledBubble] == nil)
        #expect(originals.batchAnchor == newAnchor)
        #expect(originals.map[newAnchor] == .batch(["A", "B"]))
    }

    @Test func `recordCancellation of non-run id leaves run key tracking intact`() {
        var originals = RequestOriginals()
        let runKey = UUID()
        let other = UUID()
        originals.map[runKey] = .batch(["A"])
        originals.map[other] = .batch(["A"])

        let next = originals.recordCancellation(id: other, runKey: runKey)
        #expect(next == runKey)
        #expect(originals.map[other] == nil)
        #expect(originals.map[runKey] == .batch(["A"]))
    }

    @Test func `clearMatching removes every entry with the same request value`() {
        var originals = RequestOriginals()
        let firstA = UUID()
        let onlyB = UUID()
        let secondA = UUID()
        originals.map = [firstA: .batch(["A"]), onlyB: .batch(["B"]), secondA: .batch(["A"])]

        originals.clearMatching(.batch(["A"]))
        #expect(originals.map[firstA] == nil)
        #expect(originals.map[secondA] == nil)
        #expect(originals.map[onlyB] == .batch(["B"]))
    }

    @Test func `clearRunKey is a no-op for nil and removes only that key`() {
        var originals = RequestOriginals()
        let keep = UUID()
        let drop = UUID()
        originals.map = [keep: .batch(["A"]), drop: .batch(["B"])]

        originals.clearRunKey(nil)
        originals.clearRunKey(drop)
        #expect(originals.map[keep] == .batch(["A"]))
        #expect(originals.map[drop] == nil)
    }
}
