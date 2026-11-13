#if DEBUG
    @testable import AIChat
    import Testing
    import UIKit

    /// DEBUG 키워드 계약 (`docs/qa-keywords.md`).
    /// 제거: 이 파일 + `MockChatService+QAKeywords.swift` + `send`의 `#if DEBUG` 블록.
    @MainActor
    struct MockChatServiceQAKeywordTests {
        private func text(of stream: AsyncThrowingStream<String, Error>) async throws -> String {
            var collected = ""
            for try await chunk in stream {
                collected += chunk
            }
            return collected
        }

        private func collectAll(_ streams: [AsyncThrowingStream<String, Error>]) async throws -> [String] {
            var result: [String] = []
            for stream in streams {
                try await result.append(text(of: stream))
            }
            return result
        }

        // MARK: - Parse

        @Test func `parse strips keywords and keeps remainder`() {
            let directive = QADirective.parse(from: ["QA:prefix 안녕", "QA:noprefix"])
            #expect(directive.cleanedTexts == ["안녕"])
            #expect(directive.forcePrefix == false)
            #expect(directive.sawKeyword)
        }

        @Test func `parse accepts multiple tokens in one message`() {
            let directive = QADirective.parse(from: ["QA:slow QA:long 본문"])
            #expect(directive.slow)
            #expect(directive.useLongFixture)
            #expect(directive.cleanedTexts == ["본문"])
            #expect(directive.mode == .normal)
            #expect(directive.sawKeyword)
        }

        @Test func `parse maps failure keywords`() {
            #expect(QADirective.parse(from: ["QA:timeout"]).mode == .timeout)
            #expect(QADirective.parse(from: ["QA:partial-timeout"]).mode == .partialTimeout)
            #expect(QADirective.parse(from: ["QA:empty"]).mode == .empty)
            #expect(QADirective.parse(from: ["QA:network"]).mode == .throwError(.network))
            #expect(QADirective.parse(from: ["QA:decoding"]).mode == .throwError(.decoding))
            #expect(QADirective.parse(from: ["QA:unauthorized"]).mode == .throwError(.unauthorized))
            #expect(QADirective.parse(from: ["QA:unknown"]).mode == .throwError(.unknown))
        }

        @Test func `plain text is not a QA trigger`() {
            let directive = QADirective.parse(from: ["안녕하세요"])
            #expect(!directive.sawKeyword)
        }

        // MARK: - Prefix / body

        @Test func `QA prefix always returns two streams`() async throws {
            let service = MockChatService(delay: .zero, chunkDelay: .zero, includesPrefix: { false })
            let streams = service.send(["QA:prefix 질문"])
            #expect(streams.count == 2)
            let texts = try await collectAll(streams)
            #expect(!texts[0].isEmpty)
            #expect(texts[1].contains("질문"))
            #expect(!texts[1].contains("QA:prefix"))
        }

        @Test func `QA noprefix always returns one stream even if random would prefix`() async throws {
            let service = MockChatService(delay: .zero, chunkDelay: .zero, includesPrefix: { true })
            let streams = service.send(["QA:noprefix 질문"])
            #expect(streams.count == 1)
            #expect(try await text(of: streams[0]).contains("질문"))
        }

        @Test func `QA long returns long fixture`() async throws {
            let service = MockChatService(delay: .zero, chunkDelay: .zero, includesPrefix: { false })
            let answer = try await text(of: service.send(["QA:long"])[0])
            #expect(answer == MockChatService.longFixture)
            let lineCount = MessageLineLimit.lineCount(
                text: answer, font: .systemFont(ofSize: 17), width: 300,
            )
            #expect(lineCount > MessageLineLimit.collapsedLines)
        }

        /// `slow`는 청크/글자 지연에 400ms/200ms 하한을 강제하므로, longFixture(700자+) 전체를 실시간으로
        /// 다 받으면 테스트가 수십 초 걸린다. 앞부분만 확인하고 조기 종료해 비용을 낮춘다.
        @Test func `QA slow alone returns long fixture for visible chunk delay`() async throws {
            let service = MockChatService(delay: .zero, chunkDelay: .zero, includesPrefix: { false })
            let stream = service.send(["QA:slow 안녕"])[0]
            var collected = ""
            for try await chunk in stream {
                collected += chunk
                if collected.count >= 20 {
                    break
                }
            }
            #expect(MockChatService.longFixture.hasPrefix(collected))
        }

        @Test func `QA slow plus short keeps short fixture`() async throws {
            let service = MockChatService(delay: .zero, chunkDelay: .zero, includesPrefix: { false })
            let answer = try await text(of: service.send(["QA:slow QA:short"])[0])
            #expect(answer == MockChatService.shortFixture)
        }

        @Test func `QA short returns short fixture`() async throws {
            let service = MockChatService(delay: .zero, chunkDelay: .zero, includesPrefix: { false })
            let answer = try await text(of: service.send(["QA:short"])[0])
            #expect(answer == MockChatService.shortFixture)
        }

        @Test func `QA bold italic strike return markdown fixtures without prefix`() async throws {
            let service = MockChatService(delay: .zero, chunkDelay: .zero, includesPrefix: { true })
            #expect(QADirective.parse(from: ["QA:bold"]).markdownFixture == .bold)
            #expect(QADirective.parse(from: ["QA:italic"]).markdownFixture == .italic)
            #expect(QADirective.parse(from: ["QA:strike"]).markdownFixture == .strike)

            let boldStreams = service.send(["QA:bold"])
            #expect(boldStreams.count == 1)
            #expect(try await text(of: boldStreams[0]) == MockChatService.boldMarkdownFixture)

            let italicStreams = service.send(["QA:italic"])
            #expect(italicStreams.count == 1)
            #expect(try await text(of: italicStreams[0]) == MockChatService.italicMarkdownFixture)

            let strikeStreams = service.send(["QA:strike"])
            #expect(strikeStreams.count == 1)
            #expect(try await text(of: strikeStreams[0]) == MockChatService.strikeMarkdownFixture)
        }

        @Test func `without keywords random path is unchanged`() async throws {
            let service = MockChatService(delay: .zero, chunkDelay: .zero, includesPrefix: { false })
            let streams = service.send(["안녕하세요"])
            #expect(streams.count == 1)
            #expect(try await text(of: streams[0]) == "'안녕하세요'라고 하셨네요.")
        }

        // MARK: - Failures

        @Test func `QA network throws after delay`() async throws {
            let service = MockChatService(delay: .zero, chunkDelay: .zero, includesPrefix: { true })
            let streams = service.send(["QA:network"])
            #expect(streams.count == 1)
            await #expect(throws: ChatServiceError.network) {
                _ = try await text(of: streams[0])
            }
        }

        @Test func `QA decoding throws non-retryable error`() async throws {
            let service = MockChatService(delay: .zero, chunkDelay: .zero, includesPrefix: { false })
            let streams = service.send(["QA:decoding"])
            #expect(streams.count == 1)
            await #expect(throws: ChatServiceError.decoding) {
                _ = try await text(of: streams[0])
            }
            #expect(!ChatServiceError.decoding.isRetryable)
        }

        @Test func `QA empty finishes without chunks`() async throws {
            let service = MockChatService(delay: .zero, chunkDelay: .zero, includesPrefix: { false })
            let answer = try await text(of: service.send(["QA:empty"])[0])
            #expect(answer.isEmpty)
        }

        @Test func `QA prefix plus network keeps prefix then fails answer`() async throws {
            let service = MockChatService(delay: .zero, chunkDelay: .zero, includesPrefix: { false })
            let streams = service.send(["QA:prefix QA:network"])
            #expect(streams.count == 2)
            #expect(try await !text(of: streams[0]).isEmpty)
            await #expect(throws: ChatServiceError.network) {
                _ = try await text(of: streams[1])
            }
        }

        /// sleep+cancel 대신 IdleTimeoutStream으로 끊는다 — 부하 flake 방지.
        @Test func `QA timeout yields nothing and IdleTimeoutStream throws`() async throws {
            let service = MockChatService(
                delay: .zero, chunkDelay: .zero, timeoutInterval: 10, includesPrefix: { false },
            )
            let raw = service.send(["QA:timeout"])[0]
            let watched = IdleTimeoutStream.make(from: raw, interval: .milliseconds(100))

            await #expect(throws: ChatServiceError.timeout) {
                for try await _ in watched {}
            }
        }

        @Test func `QA partial-timeout yields text then IdleTimeoutStream throws`() async throws {
            let service = MockChatService(
                delay: .zero, chunkDelay: .zero, timeoutInterval: 10, includesPrefix: { false },
            )
            let raw = service.send(["QA:partial-timeout 긴질문텍스트"])[0]
            let watched = IdleTimeoutStream.make(from: raw, interval: .milliseconds(100))

            var collected = ""
            await #expect(throws: ChatServiceError.timeout) {
                for try await chunk in watched {
                    collected += chunk
                }
            }
            #expect(!collected.isEmpty)
        }

        @Test func `QA partial-timeout with no extra text cuts off before sentence completes`() async throws {
            let service = MockChatService(
                delay: .zero, chunkDelay: .zero, timeoutInterval: 10, includesPrefix: { false },
            )
            let raw = service.send(["QA:partial-timeout"])[0]
            let watched = IdleTimeoutStream.make(from: raw, interval: .milliseconds(100))

            var collected = ""
            await #expect(throws: ChatServiceError.timeout) {
                for try await chunk in watched {
                    collected += chunk
                }
            }
            #expect(collected == "'QA'라고 하셨")
        }
    }
#endif
