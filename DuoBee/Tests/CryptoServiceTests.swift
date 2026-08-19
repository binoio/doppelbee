//
//  CryptoServiceTests.swift
//  DuoBeeTests
//
//  Created on 2026-01-04.
//  SPDX-License-Identifier: AGPL-3.0-or-later
//

import XCTest
@testable import DuoBee

final class CryptoServiceTests: XCTestCase {
    var cryptoService: CryptoService!

    override func setUp() {
        super.setUp()
        cryptoService = CryptoService()
    }

    override func tearDown() {
        cryptoService = nil
        super.tearDown()
    }

    func testEncryptDecrypt() throws {
        let originalData = "Hello, DuoBee!".data(using: .utf8)!
        let password = "test_password_123"

        // Encrypt the data
        let encryptedData = try cryptoService.encrypt(originalData, password: password)

        // Verify encrypted data is different and has the correct format
        XCTAssertNotEqual(encryptedData, originalData)
        XCTAssertGreaterThan(encryptedData.count, originalData.count)

        // Check header
        let header = String(data: encryptedData.prefix(4), encoding: .utf8)
        XCTAssertEqual(header, "DBv1")

        // Decrypt the data
        let decryptedData = try cryptoService.decrypt(encryptedData, password: password)

        // Verify decrypted data matches original
        XCTAssertEqual(decryptedData, originalData)
    }

    func testDecryptWithWrongPassword() {
        let originalData = "Secret data".data(using: .utf8)!
        let correctPassword = "correct_password"
        let wrongPassword = "wrong_password"

        do {
            let encryptedData = try cryptoService.encrypt(originalData, password: correctPassword)

            // This should throw an error
            _ = try cryptoService.decrypt(encryptedData, password: wrongPassword)
            XCTFail("Decryption should fail with wrong password")
        } catch {
            // Expected to fail
            XCTAssertTrue(true)
        }
    }

    func testEncryptionProducesDifferentOutput() throws {
        let originalData = "Test data".data(using: .utf8)!
        let password = "password"

        // Encrypt the same data twice
        let encrypted1 = try cryptoService.encrypt(originalData, password: password)
        let encrypted2 = try cryptoService.encrypt(originalData, password: password)

        // Due to random salt, encrypted data should be different each time
        XCTAssertNotEqual(encrypted1, encrypted2)

        // But both should decrypt to the same original data
        let decrypted1 = try cryptoService.decrypt(encrypted1, password: password)
        let decrypted2 = try cryptoService.decrypt(encrypted2, password: password)

        XCTAssertEqual(decrypted1, originalData)
        XCTAssertEqual(decrypted2, originalData)
    }

    func testInvalidHeaderThrowsError() {
        let invalidData = "XXXX".data(using: .utf8)! + Data(repeating: 0, count: 50)
        let password = "password"

        XCTAssertThrowsError(try cryptoService.decrypt(invalidData, password: password)) { error in
            XCTAssertTrue(error is CryptoError)
        }
    }
}
