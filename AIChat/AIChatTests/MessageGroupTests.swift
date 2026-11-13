@testable import AIChat
import Testing

struct MessageGroupTests {
    @Test func `consecutive same sender messages are grouped together`() {
        let messages = [
            Message(sender: .user, text: "1", status: .completed),
            Message(sender: .user, text: "2", status: .completed),
            Message(sender: .user, text: "3", status: .completed),
        ]

        let groups = MessageGroup.makeGroups(from: messages)

        #expect(groups.count == 1)
        #expect(groups[0].messages.count == 3)
    }

    @Test func `sender change starts a new group`() {
        let messages = [
            Message(sender: .user, text: "1", status: .completed),
            Message(sender: .user, text: "2", status: .completed),
            Message(sender: .ai, text: "3", status: .completed),
            Message(sender: .user, text: "4", status: .completed),
        ]

        let groups = MessageGroup.makeGroups(from: messages)

        #expect(groups.count == 3)
        #expect(groups[0].sender == .user)
        #expect(groups[1].sender == .ai)
        #expect(groups[2].sender == .user)
    }

    @Test func `empty input produces empty groups`() {
        #expect(MessageGroup.makeGroups(from: []).isEmpty)
    }

    @Test func `single message produces a single group with one message`() {
        let message = Message(sender: .ai, text: "hi", status: .completed)

        let groups = MessageGroup.makeGroups(from: [message])

        #expect(groups.count == 1)
        #expect(groups[0].messages == [message])
    }

    @Test func `alternating senders produce one group per message`() {
        let messages = [
            Message(sender: .user, text: "1", status: .completed),
            Message(sender: .ai, text: "2", status: .completed),
            Message(sender: .user, text: "3", status: .completed),
            Message(sender: .ai, text: "4", status: .completed),
        ]

        let groups = MessageGroup.makeGroups(from: messages)

        #expect(groups.count == messages.count)
    }

    @Test func `group preserves message order`() {
        let messages = [
            Message(sender: .user, text: "1", status: .completed),
            Message(sender: .user, text: "2", status: .completed),
            Message(sender: .user, text: "3", status: .completed),
        ]

        let groups = MessageGroup.makeGroups(from: messages)

        #expect(groups[0].messages.map(\.text) == ["1", "2", "3"])
    }

    @Test func `group id matches first message id`() {
        let messages = [
            Message(sender: .user, text: "1", status: .completed),
            Message(sender: .user, text: "2", status: .completed),
        ]

        let groups = MessageGroup.makeGroups(from: messages)

        #expect(groups[0].id == messages[0].id)
    }

    @Test func `groupedMessages marks only the first and last message in a multi-message group`() {
        let messages = [
            Message(sender: .ai, text: "1", status: .completed),
            Message(sender: .ai, text: "2", status: .completed),
            Message(sender: .ai, text: "3", status: .completed),
        ]

        let group = MessageGroup.makeGroups(from: messages)[0]

        #expect(group.groupedMessages.map(\.isFirstInGroup) == [true, false, false])
        #expect(group.groupedMessages.map(\.isLastInGroup) == [false, false, true])
    }

    @Test func `groupedMessages marks a single-message group as both first and last`() {
        let message = Message(sender: .ai, text: "hi", status: .completed)

        let group = MessageGroup.makeGroups(from: [message])[0]

        #expect(group.groupedMessages.count == 1)
        #expect(group.groupedMessages[0].isFirstInGroup)
        #expect(group.groupedMessages[0].isLastInGroup)
    }

    @Test func `status differences do not break grouping`() {
        let messages = [
            Message(sender: .ai, text: "1", status: .pending),
            Message(sender: .ai, text: "2", status: .streaming),
            Message(sender: .ai, text: "3", status: .completed),
        ]

        let groups = MessageGroup.makeGroups(from: messages)

        #expect(groups.count == 1)
        #expect(groups[0].messages.count == 3)
    }
}
