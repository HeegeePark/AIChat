import SwiftUI

struct MessageInputView: View {
    @Binding var text: String
    let canSend: Bool
    let canStop: Bool
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void
    let onStop: () -> Void

    private var isInputEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("메시지 입력", text: $text, axis: .vertical)
                .focused(isFocused)
                .lineLimit(1 ... 3)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .accessibilityLabel("메시지")
                .accessibilityIdentifier("messageInput")

            trailingAction
        }
        .padding()
    }

    @ViewBuilder
    private var trailingAction: some View {
        if canSend {
            sendButton
        } else if canStop {
            Button(action: onStop) {
                Image(systemName: "stop.circle.fill")
                    .font(.title)
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("생성 중지")
            .accessibilityIdentifier("stopButton")
        } else {
            sendButton
        }
    }

    private var sendButton: some View {
        Button(action: onSend) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.title)
        }
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel("전송")
        .accessibilityHint(isInputEmpty ? "메시지를 입력하세요" : "")
        .accessibilityIdentifier("sendButton")
        .disabled(!canSend)
    }
}

private struct MessageInputPreview: View {
    @FocusState private var isFocused: Bool

    var body: some View {
        MessageInputView(
            text: .constant(""),
            canSend: false,
            canStop: false,
            isFocused: $isFocused,
            onSend: {},
            onStop: {},
        )
    }
}

#Preview {
    MessageInputPreview()
}
