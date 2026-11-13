#if DEBUG
    import Foundation

    // MARK: - 제거 방법

    // 1. 이 파일 삭제
    // 2. `MockChatService.send`의 `#if DEBUG` 블록 제거
    // 3. `MockChatServiceQAKeywordTests.swift` 삭제
//
    // 키워드 추가: `keywordTable` 한 줄 (+ 필요 시 `qaAnswerStream` 분기).

    /// DEBUG Mock 전용 QA 키워드 계약 (`docs/qa-keywords.md`).
    nonisolated struct QADirective: Sendable, Equatable {
        enum Mode: Sendable, Equatable {
            case normal
            case timeout
            case partialTimeout
            case empty
            case throwError(ChatServiceError)
        }

        /// 파서가 인식하는 토큰 효과. 표에 없는 `QA:…`는 무시한다.
        private enum Effect: Sendable {
            case forcePrefix(Bool)
            case long
            case short
            case slow
            case mdBold
            case mdItalic
            case mdStrike
            case mode(Mode)
        }

        /// 인라인 마크다운 픽스처. 마지막에 적용된 토큰이 이긴다.
        enum MarkdownFixture: Sendable, Equatable {
            case bold
            case italic
            case strike
        }

        /// 키워드 추가·삭제는 이 표만 고친다.
        private static let keywordTable: [String: Effect] = [
            "prefix": .forcePrefix(true),
            "noprefix": .forcePrefix(false),
            "long": .long,
            "short": .short,
            "slow": .slow,
            "bold": .mdBold,
            "italic": .mdItalic,
            "strike": .mdStrike,
            "timeout": .mode(.timeout),
            "partial-timeout": .mode(.partialTimeout),
            "empty": .mode(.empty),
            "network": .mode(.throwError(.network)),
            "decoding": .mode(.throwError(.decoding)),
            "unauthorized": .mode(.throwError(.unauthorized)),
            "unknown": .mode(.throwError(.unknown)),
        ]

        private struct Builder {
            var forcePrefix: Bool?
            var useLong = false
            var useShort = false
            var slow = false
            var markdownFixture: MarkdownFixture?
            var mode: Mode = .normal
            var cleaned: [String] = []
            var sawKeyword = false

            mutating func apply(_ token: String) {
                guard let effect = keywordTable[token] else { return }
                switch effect {
                case let .forcePrefix(value):
                    forcePrefix = value
                case .long:
                    useLong = true
                    useShort = false
                    markdownFixture = nil
                case .short:
                    useShort = true
                    useLong = false
                    markdownFixture = nil
                case .slow:
                    slow = true
                case .mdBold:
                    markdownFixture = .bold
                    useLong = false
                    useShort = false
                case .mdItalic:
                    markdownFixture = .italic
                    useLong = false
                    useShort = false
                case .mdStrike:
                    markdownFixture = .strike
                    useLong = false
                    useShort = false
                case let .mode(value):
                    mode = value
                }
            }

            func make() -> QADirective {
                QADirective(
                    cleanedTexts: cleaned,
                    forcePrefix: forcePrefix,
                    useLongFixture: useLong,
                    useShortFixture: useShort,
                    markdownFixture: markdownFixture,
                    slow: slow,
                    mode: mode,
                    sawKeyword: sawKeyword,
                )
            }
        }

        var cleanedTexts: [String]
        var forcePrefix: Bool?
        var useLongFixture: Bool
        var useShortFixture: Bool
        var markdownFixture: MarkdownFixture?
        var slow: Bool
        var mode: Mode

        /// `QA:` 토큰을 하나라도 봤으면 true — 기본 `send`와의 분기 기준.
        private(set) var sawKeyword: Bool

        /// 실패·timeout·마크다운 픽스처는 랜덤 프리픽스를 끄고 말풍선 개수를 고정. 명시적 `QA:prefix`만 예외.
        var locksPrefixOff: Bool {
            mode != .normal || markdownFixture != nil
        }

        static func parse(from texts: [String]) -> QADirective {
            var builder = Builder()
            for text in texts {
                let (tokens, remainder) = extractTokens(from: text)
                if !tokens.isEmpty {
                    builder.sawKeyword = true
                }
                for token in tokens {
                    builder.apply(token)
                }
                let trimmed = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    builder.cleaned.append(trimmed)
                }
            }
            return builder.make()
        }

        private static func extractTokens(from text: String) -> (tokens: [String], remainder: String) {
            var tokens: [String] = []
            var remainderParts: [String] = []
            let pattern = #"QA:([A-Za-z0-9-]+)"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return ([], text)
            }
            let nsString = text as NSString
            let fullRange = NSRange(location: 0, length: nsString.length)
            var lastEnd = 0
            regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                guard let match, match.numberOfRanges >= 2 else { return }
                let tokenRange = match.range(at: 1)
                if let swiftRange = Range(tokenRange, in: text) {
                    tokens.append(String(text[swiftRange]).lowercased())
                }
                let gap = NSRange(location: lastEnd, length: match.range.location - lastEnd)
                if gap.length > 0 {
                    remainderParts.append(nsString.substring(with: gap))
                }
                lastEnd = match.range.location + match.range.length
            }
            if lastEnd < nsString.length {
                remainderParts.append(nsString.substring(from: lastEnd))
            }
            let remainder = remainderParts.joined()
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (tokens, remainder)
        }
    }

    extension MockChatService {
        /// 접힘(6줄+, 5줄 초과) 검증용. 개행 없는 임의의 장문(약 1000자)으로 줄바꿈 래핑을 통해 줄 수를 확보한다.
        nonisolated static let longFixture =
            "오늘은 하늘이 맑고 바람이 선선하게 불어와 산책하기 좋은 날씨였습니다. 아침 일찍 일어나 창문을 열자 새소리가 들려왔고, 멀리 보이는 산등성이에는 옅은 안개가 걸려 있었습니다. " +
            "커피 한 잔을 내려 마시며 오늘 하루의 일정을 천천히 정리해 보았습니다. 오전에는 밀린 이메일에 답장을 하고, 지난주에 시작한 프로젝트의 진행 상황을 다시 점검했습니다. " +
            "예상보다 시간이 오래 걸리는 부분이 있어 계획을 조금 수정해야 했지만, 큰 틀에서는 순조롭게 진행되고 있었습니다. 점심시간에는 근처 공원을 잠깐 걸으며 머리를 식혔습니다. " +
            "벤치에 앉아 지나가는 사람들을 구경하고, 나무 사이로 비치는 햇살을 바라보니 마음이 한결 편안해졌습니다. " +
            "오후에는 팀원들과 짧은 회의를 하고, 다음 주까지 마무리해야 할 작업들을 다시 한 번 확인했습니다. " +
            "회의가 끝난 뒤에는 자료를 정리하고 보고서 초안을 작성하는 데 시간을 보냈습니다. 생각보다 다뤄야 할 내용이 많아서 집중력이 필요했지만, 하나씩 정리하다 보니 어느새 얼개가 잡혔습니다. " +
            "저녁이 되자 하늘이 붉게 물들기 시작했고, 퇴근길에 잠시 걸음을 멈추고 노을을 바라보았습니다. 하루를 마무리하며 오늘 배운 것과 아쉬웠던 점을 간단히 메모해 두었습니다. " +
            "내일은 오늘보다 조금 더 여유 있게 하루를 시작하고, 미뤄두었던 책도 조금씩 읽어볼 생각입니다. 작은 습관들이 모여 결국 더 나은 하루를 만든다는 것을 다시 한 번 느낀 하루였습니다. " +
            "이런 하루하루가 쌓여 한 달이 되고, 한 달이 쌓여 일 년이 된다는 사실을 떠올리면 사소한 순간들도 소중하게 느껴집니다. " +
            "앞으로도 무리하지 않는 선에서 꾸준히 기록하고 돌아보는 습관을 이어가고 싶습니다. " +
            "특히 바쁘다는 핑계로 미뤄두었던 운동을 다시 시작하고, 주말에는 가족들과 시간을 보내며 재충전하는 것도 잊지 않으려 합니다. " +
            "멀리 내다보면 결국 중요한 것은 거창한 계획이 아니라 매일 조금씩 실천하는 꾸준함이라는 생각이 듭니다. 그런 마음가짐으로 남은 한 주도 차분하게 보내려 합니다."

        nonisolated static let shortFixture = "네, 확인했습니다."

        /// 인라인 마크다운 완료 AI 말풍선 육안·단위 검증용. 마커 포함 원문.
        nonisolated static let boldMarkdownFixture =
            "이 문장에 **굵은 강조**가 포함됩니다. 완료 후 마커 없이 굵게 보여야 합니다."
        nonisolated static let italicMarkdownFixture =
            "이 문장에 *기울임 강조*가 포함됩니다. 완료 후 마커 없이 기울여 보여야 합니다."
        nonisolated static let strikeMarkdownFixture =
            "이 문장에 ~~취소선 강조~~가 포함됩니다. 완료 후 마커 없이 취소선이 보여야 합니다."

        /// 키워드가 없으면 nil → 기본 `send` 경로.
        func qaKeywordStreams(for texts: [String]) -> [AsyncThrowingStream<String, Error>]? {
            let directive = QADirective.parse(from: texts)
            guard directive.sawKeyword else { return nil }

            let answer = qaAnswerText(cleaned: directive.cleanedTexts, directive: directive)
            let initialDelay = directive.slow ? max(delay, .milliseconds(400)) : delay
            let betweenChunks = directive.slow ? max(chunkDelay, .milliseconds(200)) : chunkDelay

            let wantPrefix: Bool = if let forced = directive.forcePrefix {
                forced
            } else if directive.locksPrefixOff {
                false
            } else {
                includesPrefix()
            }

            var streams: [AsyncThrowingStream<String, Error>] = []
            if wantPrefix {
                let phrase = Self.prefixPhrases.randomElement() ?? Self.prefixPhrases[0]
                streams.append(stream(of: phrase, delay: initialDelay, chunkDelay: betweenChunks))
            }
            streams.append(
                qaAnswerStream(
                    answer: answer,
                    directive: directive,
                    delay: initialDelay,
                    chunkDelay: betweenChunks,
                ),
            )
            return streams
        }

        private func qaAnswerText(cleaned: [String], directive: QADirective) -> String {
            if let markdown = directive.markdownFixture {
                switch markdown {
                case .bold:
                    return Self.boldMarkdownFixture
                case .italic:
                    return Self.italicMarkdownFixture
                case .strike:
                    return Self.strikeMarkdownFixture
                }
            }
            if directive.useLongFixture {
                return Self.longFixture
            }
            if directive.useShortFixture {
                return Self.shortFixture
            }
            if directive.slow {
                return Self.longFixture
            }
            let joined = cleaned.joined(separator: "' 그리고 '")
            let body = joined.isEmpty ? "QA" : joined
            return "'\(body)'라고 하셨네요."
        }

        private func qaAnswerStream(
            answer: String,
            directive: QADirective,
            delay: Duration,
            chunkDelay: Duration,
        ) -> AsyncThrowingStream<String, Error> {
            switch directive.mode {
            case .normal:
                return stream(of: answer, delay: delay, chunkDelay: chunkDelay)
            case .timeout:
                return hangStream(afterChunks: [], delay: delay)
            case .partialTimeout:
                let partial = String(answer.prefix(9))
                return hangStream(afterChunks: partial.isEmpty ? ["…"] : [partial], delay: delay)
            case .empty:
                return delayedFinish(delay: delay)
            case let .throwError(error):
                return delayedThrow(error, delay: delay)
            }
        }

        /// 청크 후 hang → ViewModel의 `IdleTimeoutStream`이 `.timeout`을 낸다.
        private func hangStream(
            afterChunks: [String],
            delay: Duration,
        ) -> AsyncThrowingStream<String, Error> {
            let hangSeconds = max(timeoutInterval * 3, 1)
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        try await Task.sleep(for: delay)
                        for chunk in afterChunks where !chunk.isEmpty {
                            continuation.yield(chunk)
                        }
                        try await Task.sleep(for: .seconds(hangSeconds))
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }

        private func delayedFinish(delay: Duration) -> AsyncThrowingStream<String, Error> {
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        try await Task.sleep(for: delay)
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }

        private func delayedThrow(
            _ error: ChatServiceError,
            delay: Duration,
        ) -> AsyncThrowingStream<String, Error> {
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        try await Task.sleep(for: delay)
                        continuation.finish(throwing: error)
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    }
#endif
