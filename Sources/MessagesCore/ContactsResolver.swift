import Contacts

// Apple's CNContactStore invokes enumerateContacts' block once per contact,
// sequentially, from a single background thread — never in parallel with
// itself — so plain (unlocked) mutation here is safe.
private final class NameAccumulator: @unchecked Sendable {
    var phoneMap: [String: String] = [:]
    var emailMap: [String: String] = [:]
}

public final class ContactsResolver {
    private var nameByNormalizedPhone: [String: String] = [:]
    private var nameByEmail: [String: String] = [:]

    public init() {}

    public func loadContacts() async throws {
        let store = CNContactStore()
        guard try await store.requestAccess(for: .contacts) else { return }

        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)

        // enumerateContacts invokes its block from a background thread, not the
        // caller's thread/actor, once per contact sequentially (per Apple's docs —
        // not in parallel, so no lock needed for the accumulation itself). Build
        // into a local accumulator here — never touch self's stored properties
        // mid-enumeration, or a concurrent main-thread read (displayName, called
        // while SwiftUI renders) races this write and can crash (EXC_BAD_ACCESS
        // reading a Dictionary mid-mutation).
        let accumulator = NameAccumulator()
        try store.enumerateContacts(with: request) { contact, _ in
            guard let name = CNContactFormatter.string(from: contact, style: .fullName), !name.isEmpty else { return }
            for phone in contact.phoneNumbers {
                accumulator.phoneMap[Self.normalizePhone(phone.value.stringValue)] = name
            }
            for email in contact.emailAddresses {
                accumulator.emailMap[(email.value as String).lowercased()] = name
            }
        }

        // Publish once, fully built, on the main actor — the same thread every
        // read happens on — so no reader ever observes a half-written dictionary.
        await MainActor.run {
            self.nameByNormalizedPhone = accumulator.phoneMap
            self.nameByEmail = accumulator.emailMap
        }
    }

    public func displayName(for handle: String?) -> String? {
        guard let handle else { return nil }
        if let name = nameByEmail[handle.lowercased()] { return name }
        let normalized = Self.normalizePhone(handle)
        return normalized.isEmpty ? nil : nameByNormalizedPhone[normalized]
    }

    // Compares by last 10 digits so "+1 (205) 821-5479", "12058215479" and
    // "205-821-5479" all match regardless of country-code/formatting differences.
    static func normalizePhone(_ raw: String) -> String {
        String(raw.filter(\.isNumber).suffix(10))
    }
}
