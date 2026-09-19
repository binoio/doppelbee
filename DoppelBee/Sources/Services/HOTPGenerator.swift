//
//  HOTPGenerator.swift
//  DoppelBee
//
//  Created on 2026-01-04.
//  SPDX-License-Identifier: AGPL-3.0-or-later
//

import Foundation
import CryptoKit

class HOTPGenerator {
    func generate(secret: String, counter: Int) throws -> String {
        // Decode base32 secret
        guard let keyData = base32Decode(secret) else {
            throw HOTPError.invalidSecret
        }

        // Convert counter to big-endian bytes
        var counterBytes = withUnsafeBytes(of: counter.bigEndian) { Data($0) }

        // Use UInt64 for proper 8-byte counter
        var counter64 = UInt64(counter).bigEndian
        let counterData = Data(bytes: &counter64, count: 8)

        // HMAC-SHA1
        let key = SymmetricKey(data: keyData)
        let hmac = HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: key)
        let hmacData = Data(hmac)

        // Dynamic truncation
        let offset = Int(hmacData[hmacData.count - 1] & 0x0f)
        let truncatedHash = hmacData.subdata(in: offset..<offset + 4)

        var value = truncatedHash.withUnsafeBytes { $0.load(as: UInt32.self) }
        value = UInt32(bigEndian: value) & 0x7fffffff

        // Generate 6-digit code
        let code = String(format: "%06d", value % 1_000_000)
        return code
    }

    private func base32Decode(_ string: String) -> Data? {
        let base32Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        var bits = ""

        for char in string.uppercased() {
            guard let index = base32Alphabet.firstIndex(of: char) else {
                if char == "=" { break }
                continue
            }
            let value = base32Alphabet.distance(from: base32Alphabet.startIndex, to: index)
            bits += String(value, radix: 2).leftPadding(toLength: 5, withPad: "0")
        }

        var data = Data()
        for i in stride(from: 0, to: bits.count - 7, by: 8) {
            let byteString = String(bits.dropFirst(i).prefix(8))
            if let byte = UInt8(byteString, radix: 2) {
                data.append(byte)
            }
        }

        return data.isEmpty ? nil : data
    }
}

extension String {
    func leftPadding(toLength: Int, withPad: String) -> String {
        guard count < toLength else { return self }
        return String(repeating: withPad, count: toLength - count) + self
    }
}

enum HOTPError: LocalizedError {
    case invalidSecret

    var errorDescription: String? {
        switch self {
        case .invalidSecret:
            return "Invalid secret key"
        }
    }
}
