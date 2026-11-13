import Foundation

nonisolated struct GroupedMessage: Identifiable, Equatable, Sendable {
    let message: Message
    let isFirstInGroup: Bool
    let isLastInGroup: Bool

    var id: UUID {
        message.id
    }
}

nonisolated struct MessageGroup: Identifiable, Equatable, Sendable {
    var id: UUID {
        messages[0].id
    }

    let sender: Message.Sender
    let messages: [Message]

    /// 그룹 내 위치(첫/마지막)는 구조적 사실이라 Model이 계산 프로퍼티로 제공
    var groupedMessages: [GroupedMessage] {
        messages.enumerated().map { index, message in
            GroupedMessage(
                message: message,
                isFirstInGroup: index == 0,
                isLastInGroup: index == messages.count - 1,
            )
        }
    }

    static func makeGroups(from messages: [Message]) -> [MessageGroup] {
        var groups: [MessageGroup] = []

        for message in messages {
            if let last = groups.last, last.sender == message.sender {
                groups[groups.count - 1] = MessageGroup(sender: last.sender, messages: last.messages + [message])
            } else {
                groups.append(MessageGroup(sender: message.sender, messages: [message]))
            }
        }

        return groups
    }
}
