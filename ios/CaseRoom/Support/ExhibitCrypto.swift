/*
 * Purpose: Decrypts exhibit ciphertext downloaded from the server using
 *          CryptoKit's AES-GCM, matching the server's `cryptography` AESGCM
 *          (32-byte key, 12-byte nonce, ciphertext||16-byte tag).
 * Inputs: raw ciphertext bytes, base64 key (over the WS), base64 iv (from
 *         the exhibit manifest).
 * Outputs: decrypted plaintext bytes (a WebP image).
 * Run: consumed wherever an exhibit is downloaded and needs decrypting.
 */

import CryptoKit
import Foundation

enum ExhibitCryptoError: Error {
    case invalidKey
    case invalidIV
    case ciphertextTooShort
}

enum ExhibitCrypto {
    static func decrypt(ciphertext: Data, keyB64: String, ivB64: String) throws -> Data {
        guard let keyData = Data(base64Encoded: keyB64) else {
            throw ExhibitCryptoError.invalidKey
        }
        guard let ivData = Data(base64Encoded: ivB64) else {
            throw ExhibitCryptoError.invalidIV
        }
        guard ciphertext.count >= 16 else {
            throw ExhibitCryptoError.ciphertextTooShort
        }

        let nonce = try AES.GCM.Nonce(data: ivData)
        let tag = ciphertext.suffix(16)
        let body = ciphertext.prefix(ciphertext.count - 16)
        let sealed = try AES.GCM.SealedBox(nonce: nonce, ciphertext: body, tag: tag)
        return try AES.GCM.open(sealed, using: SymmetricKey(data: keyData))
    }
}
