//
//  CryptoService.swift
//  DuoBee
//
//  Created on 2026-01-04.
//  SPDX-License-Identifier: AGPL-3.0-or-later
//

import Foundation
import CryptoKit
import CommonCrypto

class CryptoService {
    private let magicHeader = "DBv1".data(using: .utf8)!
    private let saltLength = 16
    private let iterations = 100_000

    func encrypt(_ data: Data, password: String) throws -> Data {
        // Generate random salt
        var salt = Data(count: saltLength)
        _ = salt.withUnsafeMutableBytes { saltBytes in
            SecRandomCopyBytes(kSecRandomDefault, saltLength, saltBytes.baseAddress!)
        }

        // Derive key from password
        let key = try deriveKey(password: password, salt: salt)

        // Encrypt with AES-GCM
        let sealedBox = try AES.GCM.seal(data, using: key)

        // Combine: magic header + salt + nonce + ciphertext + tag
        var result = Data()
        result.append(magicHeader)
        result.append(salt)
        result.append(sealedBox.nonce.withUnsafeBytes { Data($0) })
        result.append(sealedBox.ciphertext)
        result.append(sealedBox.tag)

        return result
    }

    func decrypt(_ encryptedData: Data, password: String) throws -> Data {
        // Verify magic header
        let headerLength = magicHeader.count
        guard encryptedData.count > headerLength + saltLength + 12 + 16,
              encryptedData.prefix(headerLength) == magicHeader else {
            throw CryptoError.invalidFormat
        }

        var offset = headerLength

        // Extract salt
        let salt = encryptedData[offset..<offset + saltLength]
        offset += saltLength

        // Derive key
        let key = try deriveKey(password: password, salt: salt)

        // Extract nonce (12 bytes for AES-GCM)
        let nonceData = encryptedData[offset..<offset + 12]
        offset += 12
        let nonce = try AES.GCM.Nonce(data: nonceData)

        // Extract ciphertext and tag (tag is last 16 bytes)
        let ciphertextAndTag = encryptedData[offset...]
        let tagStart = ciphertextAndTag.count - 16
        let ciphertext = ciphertextAndTag.prefix(tagStart)
        let tag = ciphertextAndTag.suffix(16)

        // Decrypt
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)

        return decryptedData
    }

    private func deriveKey(password: String, salt: Data) throws -> SymmetricKey {
        guard let passwordData = password.data(using: .utf8) else {
            throw CryptoError.invalidPassword
        }

        // Use PBKDF2 with SHA256
        let derivedKey = try derivePBKDF2(password: passwordData, salt: salt, iterations: iterations, keyLength: 32)
        return SymmetricKey(data: derivedKey)
    }

    private func derivePBKDF2(password: Data, salt: Data, iterations: Int, keyLength: Int) throws -> Data {
        var derivedKeyData = Data(count: keyLength)
        let result = derivedKeyData.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                password.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        password.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyLength
                    )
                }
            }
        }

        guard result == kCCSuccess else {
            throw CryptoError.keyDerivationFailed
        }

        return derivedKeyData
    }
}

enum CryptoError: LocalizedError {
    case invalidFormat
    case invalidPassword
    case keyDerivationFailed
    case encryptionFailed
    case decryptionFailed

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid database format"
        case .invalidPassword:
            return "Invalid password"
        case .keyDerivationFailed:
            return "Key derivation failed"
        case .encryptionFailed:
            return "Encryption failed"
        case .decryptionFailed:
            return "Decryption failed"
        }
    }
}
