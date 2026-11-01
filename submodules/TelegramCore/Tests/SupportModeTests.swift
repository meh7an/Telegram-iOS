import XCTest
@testable import TelegramCore

/// Support mode is a phone starting with 424 at any length, as in TDesktop's `Helper::ShouldUse`.
/// Login used to test the prefix 42, so accounts on +420, +421 and +423 still carry a saved
/// `.supportUserInfo` attribute. A stored phone therefore outranks the attribute, which only counts
/// right after login, before the self peer has been stored.
final class SupportModeTests: XCTestCase {
    func testSupportNumbers() {
        XCTAssertTrue(isSupportAccountPhone("424"))
        XCTAssertTrue(isSupportAccountPhone("42412"))
        XCTAssertTrue(isSupportAccountPhone("4241234567"))
    }

    func testFormerRuleNumbersAreNotSupport() {
        XCTAssertFalse(isSupportAccountPhone("42777"))
        XCTAssertFalse(isSupportAccountPhone("42123"))
        XCTAssertFalse(isSupportAccountPhone("420123456789"))
        XCTAssertFalse(isSupportAccountPhone("421912345678"))
        XCTAssertFalse(isSupportAccountPhone("4233123456"))
    }

    func testOrdinaryNumbersAreNotSupport() {
        XCTAssertFalse(isSupportAccountPhone(nil))
        XCTAssertFalse(isSupportAccountPhone(""))
        XCTAssertFalse(isSupportAccountPhone("42"))
        XCTAssertFalse(isSupportAccountPhone("14241234567"))
        XCTAssertFalse(isSupportAccountPhone("971501234567"))
    }

    func testStoredPhoneOutranksAStaleAttribute() {
        XCTAssertFalse(resolvedIsSupportUser(storedPhone: "420123456789", recordAttribute: true))
    }

    func testStoredPhoneTurnsOnAnAccountWithNoAttribute() {
        XCTAssertTrue(resolvedIsSupportUser(storedPhone: "4241234567", recordAttribute: false))
    }

    func testAttributeDecidesBeforeTheSelfPeerIsStored() {
        XCTAssertTrue(resolvedIsSupportUser(storedPhone: nil, recordAttribute: true))
        XCTAssertFalse(resolvedIsSupportUser(storedPhone: nil, recordAttribute: false))
    }

    func testLostOnlyWhenThePhoneQualifiesAndTheModeIsOff() {
        XCTAssertTrue(supportModeWasLost(phone: "4241234567", isSupportUser: false))
        XCTAssertFalse(supportModeWasLost(phone: "4241234567", isSupportUser: true))
        XCTAssertFalse(supportModeWasLost(phone: "420123456789", isSupportUser: false))
        XCTAssertFalse(supportModeWasLost(phone: "420123456789", isSupportUser: true))
        XCTAssertFalse(supportModeWasLost(phone: nil, isSupportUser: false))
    }
}
