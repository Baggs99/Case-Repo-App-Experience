/*
 * Purpose: Unit tests for ExhibitCrypto's AES-GCM decryption against a
 *          real fixture produced by the server's `cryptography` AESGCM.
 * Inputs: canned base64 key/iv/ciphertext/plaintext fixture values.
 * Outputs: none.
 * Run: xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test
 */

import XCTest
@testable import CaseRoom

final class ExhibitCryptoTests: XCTestCase {

    private let keyB64 = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8="
    private let ivB64 = "AAECAwQFBgcICQoL"
    private let ctB64 = "BGOlfpeKrXatJO/j2IsRGaOw7kyEDi0ZGO61y1pEacFpMMyF26Rhvho622aW56FxGrq8AP7NGw=="
    private let expectedPlaintextB64 = "Q2FzZVJvb20gZXhoaWJpdCBmaXh0dXJlIIlQTkctaXNoIGJ5dGVz"

    func testDecryptMatchesServerFixture() throws {
        let ciphertext = Data(base64Encoded: ctB64)!
        let expected = Data(base64Encoded: expectedPlaintextB64)!

        let plaintext = try ExhibitCrypto.decrypt(ciphertext: ciphertext, keyB64: keyB64, ivB64: ivB64)

        XCTAssertEqual(plaintext, expected)
    }

    func testDecryptWithWrongKeyThrows() {
        let ciphertext = Data(base64Encoded: ctB64)!
        let wrongKeyB64 = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

        XCTAssertThrowsError(
            try ExhibitCrypto.decrypt(ciphertext: ciphertext, keyB64: wrongKeyB64, ivB64: ivB64)
        )
    }

    func testDecryptWithTruncatedCiphertextThrows() {
        let truncated = Data(base64Encoded: ctB64)!.prefix(10)

        XCTAssertThrowsError(
            try ExhibitCrypto.decrypt(ciphertext: Data(truncated), keyB64: keyB64, ivB64: ivB64)
        )
    }
}
