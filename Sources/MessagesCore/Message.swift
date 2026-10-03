import Foundation

public struct Message: Identifiable, Hashable {
    public let id: Int
    public let date: Date
    public let isFromMe: Bool
    public let text: String
    public let chatName: String
    public let handleID: String?

    public var sender: String {
        isFromMe ? "Me" : (handleID ?? chatName)
    }

    // Matches a resolved contact name (threadLabel), OR the raw chat
    // identifier/handle — by substring, and also by digits-only comparison so
    // "(559) 907-3717" matches a stored "+15599073717". That fallback is what
    // lets you find someone Contacts never resolved a name for.
    public func matchesContact(_ query: String, threadLabel: String) -> Bool {
        if threadLabel.localizedCaseInsensitiveContains(query) { return true }
        if chatName.localizedCaseInsensitiveContains(query) { return true }
        if let handleID, handleID.localizedCaseInsensitiveContains(query) { return true }

        let queryDigits = query.filter(\.isNumber)
        guard !queryDigits.isEmpty else { return false }
        if chatName.filter(\.isNumber).contains(queryDigits) { return true }
        if let handleID, handleID.filter(\.isNumber).contains(queryDigits) { return true }
        return false
    }
}
