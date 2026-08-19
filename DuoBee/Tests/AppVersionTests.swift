//
//  AppVersionTests.swift
//  DuoBeeTests
//
//  Created on 2026-08-07.
//  SPDX-License-Identifier: AGPL-3.0-or-later
//

import XCTest
@testable import DuoBee

final class AppVersionTests: XCTestCase {
    /// About and Help previously hardcoded "Version 1.0" and were never updated,
    /// so they still claimed 1.0 at release 1.2.0. Reading from the bundle keeps
    /// them honest; this guards against anyone hardcoding it again.
    func testVersionComesFromBundle() {
        let version = AppVersion.short

        XCTAssertNotEqual(version, "unknown", "Version should be readable from the bundle")
        XCTAssertFalse(version.isEmpty)

        let components = version.split(separator: ".")
        XCTAssertGreaterThanOrEqual(components.count, 2, "Expected a dotted version like 1.2.1")
        XCTAssertTrue(components.allSatisfy { $0.allSatisfy(\.isNumber) },
                      "Version components should be numeric, got '\(version)'")
    }

    func testDisplayStringIsPrefixed() {
        XCTAssertEqual(AppVersion.displayString, "Version \(AppVersion.short)")
    }

    func testNoHardcodedVersionStringsInViews() throws {
        // The test bundle runs from the build products dir; walk back to the sources.
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // DuoBee
            .appendingPathComponent("Sources/Views")

        let files = try FileManager.default.contentsOfDirectory(
            at: sourceRoot, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }

        XCTAssertFalse(files.isEmpty, "Should find view sources to scan")

        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(
                contents.contains("\"Version 1."),
                "\(file.lastPathComponent) hardcodes a version string; use AppVersion instead"
            )
        }
    }
}
