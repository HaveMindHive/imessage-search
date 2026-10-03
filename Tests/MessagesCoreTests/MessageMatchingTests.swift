import XCTest
@testable import MessagesCore

final class MessageMatchingTests: XCTestCase {
    // Exact formats observed in a real chat.db: handle.id is "+1" + 10 digits,
    // chat_identifier is the same string, and display_name is '' (empty, not
    // NULL) on nearly every 1:1 chat.
    private func message(chatName: String, handleID: String?, isFromMe: Bool = false) -> Message {
        Message(id: 1, date: .now, isFromMe: isFromMe, text: "hi", chatName: chatName, handleID: handleID)
    }

    func testUnresolvedNumberMatchesEveryWayAPersonWouldTypeIt() {
        let hers = message(chatName: "+15599073717", handleID: "+15599073717")
        for typed in ["5599073717", "559-907-3717", "(559) 907-3717", "+15599073717", "15599073717", "9073717"] {
            XCTAssertTrue(hers.matchesContact(typed, threadLabel: hers.chatName), "query \(typed) should match")
        }
    }

    func testMatchesByHandleEvenWhenChatNameIsEmpty() {
        // Pre-NULLIF loader output: chatName collapsed to '' for every 1:1 thread.
        let hers = message(chatName: "", handleID: "+15599073717")
        XCTAssertTrue(hers.matchesContact("5599073717", threadLabel: ""))
    }

    func testOutgoingRowWithoutHandleMatchesByChatName() {
        // A handful of is_from_me rows carry handle_id = 0 → handleID nil; the
        // chat identifier is the only thing left to match on.
        let mine = message(chatName: "+15599073717", handleID: nil, isFromMe: true)
        XCTAssertTrue(mine.matchesContact("5599073717", threadLabel: mine.chatName))
    }

    func testMatchesResolvedContactNameCaseInsensitively() {
        let m = message(chatName: "+12058215479", handleID: "+12058215479")
        XCTAssertTrue(m.matchesContact("mom", threadLabel: "Mom"))
    }

    func testDoesNotMatchDifferentNumberOrNonNumericJunk() {
        let m = message(chatName: "+15599073717", handleID: "+15599073717")
        XCTAssertFalse(m.matchesContact("2058215479", threadLabel: m.chatName))
        XCTAssertFalse(m.matchesContact("wife", threadLabel: m.chatName))
    }
}
