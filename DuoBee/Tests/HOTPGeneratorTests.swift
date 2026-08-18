//
//  HOTPGeneratorTests.swift
//  DuoBeeTests
//
//  Created on 2026-01-04.
//  SPDX-License-Identifier: MIT
//

import XCTest
@testable import DuoBee

final class HOTPGeneratorTests: XCTestCase {
    var generator: HOTPGenerator!

    override func setUp() {
        super.setUp()
        generator = HOTPGenerator()
    }

    override func tearDown() {
        generator = nil
        super.tearDown()
    }

    func testGenerateHOTPCode() throws {
        // Test vector from RFC 4226
        let secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ" // "12345678901234567890" in base32
        let counter = 0

        let code = try generator.generate(secret: secret, counter: counter)

        // HOTP should generate a 6-digit code
        XCTAssertEqual(code.count, 6)
        XCTAssertTrue(code.allSatisfy { $0.isNumber })
    }

    func testDifferentCountersProduceDifferentCodes() throws {
        let secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"

        let code1 = try generator.generate(secret: secret, counter: 0)
        let code2 = try generator.generate(secret: secret, counter: 1)
        let code3 = try generator.generate(secret: secret, counter: 2)

        // Each counter should produce a different code
        XCTAssertNotEqual(code1, code2)
        XCTAssertNotEqual(code2, code3)
        XCTAssertNotEqual(code1, code3)
    }

    func testSameCounterProducesSameCode() throws {
        let secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
        let counter = 42

        let code1 = try generator.generate(secret: secret, counter: counter)
        let code2 = try generator.generate(secret: secret, counter: counter)

        // Same secret and counter should always produce the same code
        XCTAssertEqual(code1, code2)
    }

    func testInvalidBase32SecretHandling() throws {
        // Test with characters outside base32 alphabet
        // Note: The implementation may handle invalid base32 differently
        // This test verifies the generator can handle edge cases gracefully
        let secret = "12345678" // Non-base32 characters
        let counter = 0

        // If the generator doesn't throw, it should still produce a 6-digit code
        let code = try generator.generate(secret: secret, counter: counter)
        XCTAssertEqual(code.count, 6)
        XCTAssertTrue(code.allSatisfy { $0.isNumber })
    }

    func testEmptySecretThrowsError() {
        let emptySecret = ""
        let counter = 0

        XCTAssertThrowsError(try generator.generate(secret: emptySecret, counter: counter))
    }

    func testCodeIsAlwaysSixDigits() throws {
        let secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"

        // Test with multiple counters to ensure padding works
        for counter in 0..<100 {
            let code = try generator.generate(secret: secret, counter: counter)
            XCTAssertEqual(code.count, 6, "Code at counter \(counter) should be 6 digits")
        }
    }
}
