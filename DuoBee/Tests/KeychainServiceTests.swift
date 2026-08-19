//
//  KeychainServiceTests.swift
//  DuoBeeTests
//
//  Created on 2026-01-04.
//  SPDX-License-Identifier: AGPL-3.0-or-later
//

import XCTest
@testable import DuoBee

final class KeychainServiceTests: XCTestCase {
    var keychainService: KeychainService!

    override func setUp() {
        super.setUp()
        // A throwaway service name per test. Using the default one would read,
        // overwrite, and delete the real database password in the user's keychain.
        keychainService = KeychainService(
            service: "com.duobee.tests.\(UUID().uuidString)",
            account: "database-password"
        )
        // Clean up any existing test data
        keychainService.deletePassword()
    }

    override func tearDown() {
        keychainService.deletePassword()
        keychainService = nil
        super.tearDown()
    }

    func testSaveAndRetrievePassword() {
        let testPassword = "test_password_123"

        // Save password
        keychainService.savePassword(testPassword)

        // Retrieve password
        let retrievedPassword = keychainService.getPassword()

        XCTAssertEqual(retrievedPassword, testPassword)
    }

    func testUpdatePassword() {
        let firstPassword = "first_password"
        let secondPassword = "second_password"

        // Save first password
        keychainService.savePassword(firstPassword)
        XCTAssertEqual(keychainService.getPassword(), firstPassword)

        // Update to second password
        keychainService.savePassword(secondPassword)
        XCTAssertEqual(keychainService.getPassword(), secondPassword)
    }

    func testDeletePassword() {
        let testPassword = "password_to_delete"

        // Save password
        keychainService.savePassword(testPassword)
        XCTAssertNotNil(keychainService.getPassword())

        // Delete password
        keychainService.deletePassword()
        XCTAssertNil(keychainService.getPassword())
    }

    func testGetPasswordWhenNoneExists() {
        // Ensure no password exists
        keychainService.deletePassword()

        // Try to retrieve non-existent password
        let password = keychainService.getPassword()

        XCTAssertNil(password)
    }

    func testMultipleSaveOperations() {
        // Test that multiple saves work correctly
        for i in 0..<5 {
            let password = "password_\(i)"
            keychainService.savePassword(password)
            XCTAssertEqual(keychainService.getPassword(), password)
        }
    }
}
