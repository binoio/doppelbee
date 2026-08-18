//
//  UpdaterConfigurationTests.swift
//  DuoBeeTests
//
//  Created on 2026-08-15.
//  SPDX-License-Identifier: MIT
//

import XCTest
@testable import DuoBee

/// Sparkle fails silently or insecurely when its Info.plist keys are wrong: a
/// bad SUPublicEDKey only surfaces when a real update is rejected, and a stray
/// SUEnableAutomaticChecks suppresses the first-run consent prompt. These run
/// against the built bundle so a misconfiguration fails here, not at release.
final class UpdaterConfigurationTests: XCTestCase {
    /// Tests are app-hosted, so Bundle.main is DuoBee.app.
    private var info: [String: Any] {
        Bundle.main.infoDictionary ?? [:]
    }

    func testFeedURLIsPresentAndSecure() throws {
        let feed = try XCTUnwrap(info["SUFeedURL"] as? String,
                                 "SUFeedURL missing from Info.plist")
        XCTAssertTrue(feed.hasPrefix("https://"),
                      "Sparkle rejects non-HTTPS feeds; got '\(feed)'")
        let url = try XCTUnwrap(URL(string: feed), "SUFeedURL is not a valid URL")
        XCTAssertEqual(url.lastPathComponent, "appcast.xml")
    }

    func testPublicKeyIsARealEd25519Key() throws {
        let key = try XCTUnwrap(info["SUPublicEDKey"] as? String,
                                "SUPublicEDKey missing from Info.plist")

        XCTAssertNotEqual(
            key, "REPLACE_WITH_GENERATE_KEYS_OUTPUT",
            """
            SUPublicEDKey is still the placeholder. Generate the signing key once:
              build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
            then paste the printed public key into DuoBee/Resources/Info.plist.
            Back up the private key — losing it means no installed copy of DuoBee
            can ever be updated again.
            """
        )

        let decoded = try XCTUnwrap(Data(base64Encoded: key),
                                    "SUPublicEDKey is not valid base64")
        XCTAssertEqual(decoded.count, 32,
                       "An Ed25519 public key is 32 bytes; got \(decoded.count)")
    }

    func testInstallerLauncherServiceIsEnabledForSandbox() {
        // Required for sandboxed apps; without it the installer XPC handshake
        // fails and updates die after download.
        XCTAssertEqual(info["SUEnableInstallerLauncherService"] as? Bool, true,
                       "Sandboxed apps require SUEnableInstallerLauncherService")
    }

    func testDownloaderServiceIsNotEnabled() {
        // Only needed when the app lacks com.apple.security.network.client,
        // which DuoBee has. Enabling it anyway adds a pointless XPC hop.
        XCTAssertNil(info["SUEnableDownloaderService"],
                     "DuoBee has network.client, so the downloader XPC is unnecessary")
    }

    func testAutomaticChecksKeyIsAbsent() {
        // Setting this either way suppresses Sparkle's first-run permission
        // prompt, which is the only consent the user is ever asked for.
        XCTAssertNil(info["SUEnableAutomaticChecks"],
                     "SUEnableAutomaticChecks must not be set; it breaks the first-run prompt")
    }

    func testEntitlementsDeclareInstallerMachServices() throws {
        // Read the source entitlements rather than the signed bundle's, so this
        // fails on an unsigned local build too.
        let entitlements = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // DuoBee
            .appendingPathComponent("Resources/DuoBee.entitlements")

        let contents = try String(contentsOf: entitlements, encoding: .utf8)

        XCTAssertTrue(contents.contains("com.apple.security.temporary-exception.mach-lookup.global-name"),
                      "Sandboxed Sparkle needs the mach-lookup exception")
        for suffix in ["-spks", "-spki"] {
            XCTAssertTrue(
                contents.contains("$(PRODUCT_BUNDLE_IDENTIFIER)\(suffix)"),
                "Missing \(suffix) mach service; Xcode substitutes the bundle id at build time"
            )
        }
        XCTAssertTrue(contents.contains("com.apple.security.app-sandbox"),
                      "The sandbox is intentional; Sparkle is configured around it")
    }
}
