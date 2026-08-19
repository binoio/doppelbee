//
//  DuoAPIServiceTests.swift
//  DuoBeeTests
//
//  Created on 2026-01-04.
//  SPDX-License-Identifier: AGPL-3.0-or-later
//

import XCTest
@testable import DuoBee

final class DuoAPIServiceTests: XCTestCase {
    var apiService: DuoAPIService!

    override func setUp() {
        super.setUp()
        apiService = DuoAPIService()
    }

    override func tearDown() {
        apiService = nil
        super.tearDown()
    }

    func testParseActivationURLValid() {
        // Test the required format: https://m-<activation-host>.duosecurity.com/activate/<activation-code>
        // Should transform to: api-<activation-host>
        let url = "https://m-example.duosecurity.com/activate/ABC123"

        let result = apiService.parseActivationURL(url)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.host, "api-example")
        XCTAssertEqual(result?.code, "ABC123")
    }

    func testParseActivationURLWithDifferentHost() {
        let url = "https://m-production.duosecurity.com/activate/XYZ789"

        let result = apiService.parseActivationURL(url)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.host, "api-production")
        XCTAssertEqual(result?.code, "XYZ789")
    }

    func testParseActivationURLInvalidDomain() {
        // Should fail for non-duosecurity.com domains
        let url = "https://m-example.otherdomain.com/activate/ABC123"

        let result = apiService.parseActivationURL(url)

        XCTAssertNil(result)
    }

    func testParseActivationURLMissingMPrefix() {
        // Should fail if host doesn't start with "m-"
        let url = "https://example.duosecurity.com/activate/ABC123"

        let result = apiService.parseActivationURL(url)

        XCTAssertNil(result)
    }

    func testParseActivationURLInvalidPath() {
        // Should fail if path doesn't contain /activate/
        let url = "https://m-example.duosecurity.com/invalidpath/ABC123"

        let result = apiService.parseActivationURL(url)

        XCTAssertNil(result)
    }

    func testParseActivationURLMissingActivationCode() {
        // Should fail if activation code is missing
        let url = "https://m-example.duosecurity.com/activate/"

        let result = apiService.parseActivationURL(url)

        XCTAssertNil(result)
    }

    func testParseActivationURLEmptyString() {
        let result = apiService.parseActivationURL("")

        XCTAssertNil(result)
    }

    func testParseActivationURLMalformed() {
        let result = apiService.parseActivationURL("not-a-valid-url")

        XCTAssertNil(result)
    }
}
