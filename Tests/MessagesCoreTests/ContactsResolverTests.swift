import XCTest
@testable import MessagesCore

final class ContactsResolverTests: XCTestCase {
    func testNormalizePhoneIgnoresFormattingAndCountryCode() {
        let forms = ["+1 (205) 821-5479", "12058215479", "205-821-5479", "(205)821.5479"]
        let normalized = Set(forms.map(ContactsResolver.normalizePhone))
        XCTAssertEqual(normalized, ["2058215479"])
    }

    func testNormalizePhoneHandlesShortNumbers() {
        XCTAssertEqual(ContactsResolver.normalizePhone("12345"), "12345")
        XCTAssertEqual(ContactsResolver.normalizePhone(""), "")
    }
}
