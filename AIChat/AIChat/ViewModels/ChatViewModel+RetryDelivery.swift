import Foundation

/// 장수명 전달 Task 공통 경계 — 스트림 대기 중 owner 강참조를 두지 않아 deinit cancel이 가능하다.
extension ChatViewModel {
    /// greeting/response/retry 공통 deliver — 각 호출의 run key는 지역 변수로 유지한다.
    nonisolated static func deliverDetached(
        _ streams: [AsyncThrowingStream<String, Error>],
        context ctx: DeliveryContext,
    ) async {
        var runKey: UUID?
        var hadFailure = false
        // finish와 clearMatching을 같은 hop에 묶지 않으면 완료 직후 맵 잔존을 관측한다.
        var clearedOnSuccess = false

        for streamIndex in streams.indices {
            let isLast = streamIndex == streams.index(before: streams.endIndex)
            let step = await consumeOneRetryStream(
                streams[streamIndex],
                runKey: runKey,
                isLastStream: isLast,
                ctx: ctx,
            )
            guard let step else {
                if Task.isCancelled {
                    await clearCancelledRun(runKey: runKey, ctx: ctx)
                }
                return
            }
            runKey = step.runKey
            if step.cleared {
                clearedOnSuccess = true
            }
            if step.failed {
                hadFailure = true
                break
            }
            if Task.isCancelled {
                break
            }
        }

        if Task.isCancelled {
            await clearCancelledRun(runKey: runKey, ctx: ctx)
        } else if !clearedOnSuccess, !hadFailure {
            await clearRetryMap(runKey: runKey, ctx: ctx)
        }
    }

    /// 스트림 하나 준비·소비·정착. owner가 사라지면 nil.
    private nonisolated static func consumeOneRetryStream(
        _ stream: AsyncThrowingStream<String, Error>,
        runKey: UUID?,
        isLastStream: Bool,
        ctx: DeliveryContext,
    ) async -> RetryStreamStep? {
        let bubbleID = UUID()
        let prepared = await MainActor.run {
            guard !Task.isCancelled, let owner = ctx.ownerRef.value else { return false }
            let previousKey = runKey ?? (
                ctx.claimsPendingBatch
                    ? owner.requestOriginals.claimRunKey(for: ctx.request)
                    : nil
            )
            owner.requestOriginals.rekey(from: previousKey, to: bubbleID, request: ctx.request)
            if let previousKey {
                owner.activeDeliveryRunIDs.remove(previousKey)
            }
            owner.activeDeliveryRunIDs.insert(bubbleID)
            owner.appendPendingAIMessage(id: bubbleID)
            owner.persist()
            return true
        }
        guard prepared else { return nil }

        let outcome = await readStream(
            stream,
            timeout: ctx.timeout,
            characterDelay: ctx.characterDelay,
        ) { character in
            await MainActor.run {
                ctx.ownerRef.value?.append(character, to: bubbleID)
            }
        }
        await ctx.settlementHook(.before)
        let step = await settleRetryStream(
            outcome: outcome,
            bubbleID: bubbleID,
            isLastStream: isLastStream,
            ctx: ctx,
        )
        await ctx.settlementHook(.after)
        return step
    }

    /// 한 스트림 종료 반영. 마지막 성공 스트림이면 맵 clear를 같은 hop에서 한다.
    private nonisolated static func settleRetryStream(
        outcome: ConsumeOutcome,
        bubbleID: UUID,
        isLastStream: Bool,
        ctx: DeliveryContext,
    ) async -> RetryStreamStep {
        await MainActor.run {
            guard let owner = ctx.ownerRef.value else {
                return RetryStreamStep(failed: true, runKey: bubbleID, cleared: false)
            }
            let effectiveOutcome: ConsumeOutcome = Task.isCancelled ? .cancelled : outcome
            var currentKey: UUID? = bubbleID
            owner.applyConsumeOutcome(effectiveOutcome, id: bubbleID, request: ctx.request, runKey: &currentKey)
            owner.finish(bubbleID, outcome: effectiveOutcome)
            var didClear = false
            if isLastStream, !effectiveOutcome.isFailed, !Task.isCancelled {
                owner.requestOriginals.clearRunKey(currentKey)
                owner.requestOriginals.clearMatching(ctx.request)
                didClear = true
            }
            switch effectiveOutcome {
            case .completed where !isLastStream:
                break
            case .completed, .cancelled, .failed:
                owner.activeDeliveryRunIDs.remove(bubbleID)
            }
            owner.persist()
            return RetryStreamStep(failed: effectiveOutcome.isFailed, runKey: currentKey, cleared: didClear)
        }
    }

    private nonisolated static func clearRetryMap(
        runKey: UUID?,
        ctx: DeliveryContext,
    ) async {
        await MainActor.run {
            guard let owner = ctx.ownerRef.value else { return }
            owner.requestOriginals.clearRunKey(runKey)
            owner.requestOriginals.clearMatching(ctx.request)
            if let runKey {
                owner.activeDeliveryRunIDs.remove(runKey)
            }
            owner.persist()
        }
    }

    private nonisolated static func clearCancelledRun(
        runKey: UUID?,
        ctx: DeliveryContext,
    ) async {
        await MainActor.run {
            guard let owner = ctx.ownerRef.value,
                  let runKey,
                  owner.activeDeliveryRunIDs.remove(runKey) != nil else { return }
            owner.requestOriginals.clearRunKey(runKey)
            owner.persist()
        }
    }

    /// 스트림을 글자 단위로 읽어 `onCharacter`에 넘긴다. owner를 붙잡지 않는다.
    nonisolated static func readStream(
        _ chunks: AsyncThrowingStream<String, Error>,
        timeout: TimeInterval,
        characterDelay: Duration,
        onCharacter: @escaping @Sendable (String) async -> Void,
    ) async -> ConsumeOutcome {
        do {
            let watched = IdleTimeoutStream.make(from: chunks, interval: .seconds(timeout))
            var received = false
            for try await character in TypewriterStream.make(from: watched, characterDelay: characterDelay) {
                if Task.isCancelled {
                    return .cancelled
                }
                received = true
                await onCharacter(character)
            }
            if Task.isCancelled {
                return .cancelled
            }
            if !received {
                return .failed(.unknown)
            }
            return .completed
        } catch is CancellationError {
            return .cancelled
        } catch let error as ChatServiceError {
            return .failed(error)
        } catch {
            return Task.isCancelled ? .cancelled : .failed(.unknown)
        }
    }
}

/// `settleRetryStream` 반환값 — large_tuple 회피.
private struct RetryStreamStep: Sendable {
    let failed: Bool
    let runKey: UUID?
    let cleared: Bool
}

nonisolated enum ConsumeOutcome: Sendable {
    case completed
    case cancelled
    case failed(ChatServiceError)

    var isFailed: Bool {
        if case .failed = self {
            return true
        }
        return false
    }
}

nonisolated enum DeliverySettlementPhase: Sendable, Equatable {
    case before
    case after
}

nonisolated struct DeliveryContext: Sendable {
    let request: FailedRequest
    let timeout: TimeInterval
    let characterDelay: Duration
    let ownerRef: WeakRef<ChatViewModel>
    let claimsPendingBatch: Bool
    let settlementHook: @Sendable (DeliverySettlementPhase) async -> Void
}

/// 재시도 Task가 owner를 파라미터/지역 강참조로 붙잡지 않게 하는 weak 상자.
final class WeakRef<T: AnyObject>: @unchecked Sendable {
    weak var value: T?

    init(_ value: T) {
        self.value = value
    }
}
