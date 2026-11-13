import SwiftUI
import UIKit

/// Zero-size host for observing the enclosing `UIScrollView` and updating bottom proximity.
///
/// **Placement (Task 3):** attach as `.background` of the ScrollView **content**
/// (e.g. `LazyVStack { … }.background { ScrollViewBottomObserver(isAtBottom: $isAtBottom) }`),
/// so the host sits under the content and walking `superview` reaches the real `UIScrollView`.
/// Do not place only on the outer `ScrollView` chrome — that tree may not ancestor-walk to it.
///
/// **Discovery:** first layout passes often lack a scroll view yet; `layoutSubviews` and a
/// main-queue async retry re-attempt attach without crashing.
struct ScrollViewBottomObserver: View {
    @Binding var isAtBottom: Bool
    /// See `ScrollBottomDetector` — trailing list spacer excluded from “at bottom”.
    var trailingSlack: CGFloat = 0
    var tolerance: CGFloat = 20
    /// Fires once per drag gesture, right as the user's finger starts moving the scroll view —
    /// before any content offset changes. Lets the owning view release a spacer/anchor exactly
    /// when the user takes over scrolling, instead of ever doing it automatically (see
    /// `ChatView`'s `postSendTopAnchorID`).
    var onDragBegin: (() -> Void)?

    var body: some View {
        ScrollViewBottomObserverRepresentable(
            isAtBottom: $isAtBottom,
            trailingSlack: trailingSlack,
            tolerance: tolerance,
            onDragBegin: onDragBegin,
        )
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - UIViewRepresentable

private struct ScrollViewBottomObserverRepresentable: UIViewRepresentable {
    @Binding var isAtBottom: Bool
    var trailingSlack: CGFloat
    var tolerance: CGFloat
    var onDragBegin: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isAtBottom: $isAtBottom,
            trailingSlack: trailingSlack,
            tolerance: tolerance,
            onDragBegin: onDragBegin,
        )
    }

    func makeUIView(context: Context) -> HostView {
        let host = HostView()
        host.isUserInteractionEnabled = false
        host.backgroundColor = .clear
        host.onLayout = { [weak coordinator = context.coordinator] view in
            coordinator?.attachIfNeeded(from: view)
        }
        context.coordinator.apply(
            isAtBottom: $isAtBottom,
            trailingSlack: trailingSlack,
            tolerance: tolerance,
            onDragBegin: onDragBegin,
        )
        // Hierarchy is often incomplete in makeUIView; retry after the next runloop turn.
        DispatchQueue.main.async { [weak coordinator = context.coordinator, weak host] in
            guard let coordinator, let host else { return }
            coordinator.attachIfNeeded(from: host)
        }
        return host
    }

    func updateUIView(_ uiView: HostView, context: Context) {
        context.coordinator.apply(
            isAtBottom: $isAtBottom,
            trailingSlack: trailingSlack,
            tolerance: tolerance,
            onDragBegin: onDragBegin,
        )
        context.coordinator.attachIfNeeded(from: uiView)
    }

    static func dismantleUIView(_ uiView: HostView, coordinator: Coordinator) {
        uiView.onLayout = nil
        coordinator.detach()
    }

    // MARK: Host

    final class HostView: UIView {
        var onLayout: ((HostView) -> Void)?

        override func layoutSubviews() {
            super.layoutSubviews()
            onLayout?(self)
        }
    }

    // MARK: Coordinator

    final class Coordinator {
        private var isAtBottom: Binding<Bool>
        private var trailingSlack: CGFloat
        private var tolerance: CGFloat
        private var onDragBegin: (() -> Void)?
        private weak var scrollView: UIScrollView?
        private var observations: [NSKeyValueObservation] = []
        /// Last value written to the binding (avoids redundant writes / button flicker).
        private var lastWritten: Bool?

        init(
            isAtBottom: Binding<Bool>,
            trailingSlack: CGFloat,
            tolerance: CGFloat,
            onDragBegin: (() -> Void)?,
        ) {
            self.isAtBottom = isAtBottom
            self.trailingSlack = trailingSlack
            self.tolerance = tolerance
            self.onDragBegin = onDragBegin
        }

        deinit {
            observations.removeAll()
            scrollView = nil
        }

        func apply(
            isAtBottom: Binding<Bool>,
            trailingSlack: CGFloat,
            tolerance: CGFloat,
            onDragBegin: (() -> Void)?,
        ) {
            self.isAtBottom = isAtBottom
            self.trailingSlack = trailingSlack
            self.tolerance = tolerance
            self.onDragBegin = onDragBegin
        }

        func detach() {
            observations.removeAll()
            scrollView = nil
            lastWritten = nil
        }

        func attachIfNeeded(from host: UIView) {
            if let existing = scrollView, existing.window != nil || existing.superview != nil {
                evaluate()
                return
            }

            guard let found = Self.enclosingScrollView(from: host) else {
                // First frames: UIScrollView may not exist yet. layoutSubviews / async retry.
                return
            }

            if scrollView !== found {
                beginObserving(found)
            }
            evaluate()
        }

        /// Walk superviews from the zero-size host toward the window; first `UIScrollView` wins.
        private static func enclosingScrollView(from view: UIView) -> UIScrollView? {
            var current: UIView? = view.superview
            while let node = current {
                if let scrollView = node as? UIScrollView {
                    return scrollView
                }
                current = node.superview
            }
            return nil
        }

        private func beginObserving(_ scrollView: UIScrollView) {
            observations.removeAll()
            self.scrollView = scrollView

            // KVO closures are nonisolated. Hop to main via DispatchQueue (no per-tick Task).
            // contentInset covers keyboard/safe-area changes that feed adjustedContentInset.
            observations = [
                scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                    self?.scheduleEvaluate()
                },
                scrollView.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
                    self?.scheduleEvaluate()
                },
                scrollView.observe(\.bounds, options: [.new]) { [weak self] _, _ in
                    self?.scheduleEvaluate()
                },
                scrollView.observe(\.contentInset, options: [.new]) { [weak self] _, _ in
                    self?.scheduleEvaluate()
                },
                // 사용자가 손가락을 대고 실제로 끌기 시작하는 순간(콘텐츠가 아직 안 움직인 시점)에만
                // 한 번 발화한다 — 그 전엔 절대 안 부른다.
                scrollView.observe(\.isTracking, options: [.new]) { [weak self] _, change in
                    guard change.newValue == true else { return }
                    self?.scheduleDragBegin()
                },
            ]
        }

        /// KVO entry point — must stay `nonisolated` under default MainActor isolation.
        private nonisolated func scheduleEvaluate() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.clampDragOverscrollIfNeeded()
                    self.evaluate()
                }
            }
        }

        /// `scrollTo(anchor: .top)`가 짧은 응답도 화면 맨 위에 고정할 수 있게 `trailingSlack`(=
        /// 스페이서)만큼 `contentSize`를 부풀려 두는데, 이 여분은 **프로그램적 스크롤 전용**이어야
        /// 한다 — 사용자가 직접 손가락으로 끌 때도 그 빈 공간까지 그대로 열리면(실측, QA 리포트:
        /// 스크린샷으로 거의 새하얀 화면까지 드래그됨) 이전에 고쳤던 자유 드래그 버그가 다시
        /// 재현된다. `isTracking`(손가락이 닿아 있는 동안) **또는 `isDecelerating`(손을 뗀 뒤
        /// 관성으로 미끄러지는 동안)**에는 진짜 콘텐츠 끝 + 여유(tolerance)를 넘는 오프셋을 즉시
        /// 그 경계로 되돌린다. `isTracking`만 걸었을 때 실측(빠른 flick 스와이프)으로 재현됨 —
        /// 손을 떼는 순간 `isTracking`은 바로 false가 되고 `isDecelerating`으로 넘어가는데, 그
        /// 관성 구간엔 클램프가 전혀 안 걸려 빈 공간까지 그대로 미끄러져 들어갔다. 두 플래그 다
        /// 순수 터치 제스처 상태라 우리 자신의 `scrollTo` 같은 프로그램적 스크롤에는 안 걸린다 —
        /// 그쪽은 스페이서를 그대로 쓴다. 같은 프로퍼티(`contentOffset`)에 다시 쓰는 것이라 KVO
        /// 재진입을 피하려고(관례상) 다음 러닝루프 틱으로 미룬다 — `scheduleEvaluate`와 동일한
        /// 이유로 `evaluate()`와 같은 훅에서 부른다.
        private func clampDragOverscrollIfNeeded() {
            guard let scrollView,
                  scrollView.isTracking || scrollView.isDecelerating,
                  trailingSlack > 0
            else { return }
            let maxRealOffsetY = max(
                0,
                scrollView.contentSize.height - trailingSlack
                    - scrollView.bounds.height + scrollView.adjustedContentInset.bottom,
            )
            let allowedOffsetY = maxRealOffsetY + tolerance
            guard scrollView.contentOffset.y > allowedOffsetY else { return }
            scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: allowedOffsetY),
                animated: false,
            )
        }

        private nonisolated func scheduleDragBegin() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.onDragBegin?()
                }
            }
        }

        private func evaluate() {
            guard let scrollView else { return }

            let atBottom = ScrollBottomDetector.isAtBottom(
                contentOffsetY: scrollView.contentOffset.y,
                contentHeight: scrollView.contentSize.height,
                viewportHeight: scrollView.bounds.height,
                adjustedContentInsetBottom: scrollView.adjustedContentInset.bottom,
                trailingSlack: trailingSlack,
                tolerance: tolerance,
            )

            guard lastWritten != atBottom else { return }
            guard isAtBottom.wrappedValue != atBottom else {
                lastWritten = atBottom
                return
            }
            lastWritten = atBottom
            isAtBottom.wrappedValue = atBottom
        }
    }
}
