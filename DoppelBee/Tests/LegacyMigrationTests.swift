//
//  LegacyMigrationTests.swift
//  DoppelBeeTests
//
//  Created on 2026-09-19.
//  SPDX-License-Identifier: AGPL-3.0-or-later
//

import XCTest
@testable import DoppelBee

final class LegacyMigrationTests: XCTestCase {

    // MARK: - Path construction

    func testRealHomeIsNotTheSandboxContainer() {
        // The whole point of going through getpwuid: inside a sandbox,
        // NSHomeDirectory() is the container, which is never where another
        // app's container lives. Tests are app-hosted, so this runs sandboxed.
        let real = LegacyMigration.realHomeDirectory.path
        XCTAssertFalse(real.contains("/Library/Containers/"),
                       "real home resolved to a container path: \(real)")
        XCTAssertTrue(real.hasPrefix("/Users/") || real.hasPrefix("/var/"),
                      "unexpected home path: \(real)")
    }

    func testOriginsCoverEveryShippedIdentity() {
        let ids = LegacyMigration.origins.map(\.bundleIdentifier)
        XCTAssertEqual(ids, ["io.bino.duobee", "edu.princeton.orfe.duobee"],
                       "newest identity must come first, and 1.x must stay reachable")
    }

    func testDatabaseURLMatchesTheDocumentedMigrationPath() {
        // This exact path is printed in the 3.0.0 release notes. If the two
        // ever disagree, the notes send people somewhere the panel does not open.
        let origin = LegacyMigration.origins[0]
        let expected = LegacyMigration.realHomeDirectory
            .appendingPathComponent("Library/Containers/io.bino.duobee/Data/Library/Application Support/DuoBee/duo.db")
        XCTAssertEqual(origin.databaseURL.standardizedFileURL, expected.standardizedFileURL)
    }

    func testSuggestedDirectoryIsTheFolderHoldingTheDatabase() {
        XCTAssertEqual(LegacyMigration.suggestedDirectory.standardizedFileURL,
                       LegacyMigration.origins[0].databaseURL
                           .deletingLastPathComponent().standardizedFileURL)
        XCTAssertEqual(LegacyMigration.suggestedDirectory.lastPathComponent, "DuoBee")
    }

    // MARK: - Migration behaviour

    /// Builds a throwaway manager whose database lives in a temp directory.
    @MainActor
    private func makeManager() throws -> (DuoDatabaseManager, URL, KeychainService) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }

        let keychain = KeychainService(service: "com.doppelbee.tests.\(UUID().uuidString)",
                                       account: "database-password")
        addTeardownBlock { keychain.deletePassword() }

        let manager = DuoDatabaseManager(
            databaseURL: dir.appendingPathComponent("duo.db"),
            keychainService: keychain,
            defaults: UserDefaults(suiteName: "com.doppelbee.tests.\(UUID().uuidString)")!,
            autoLoad: false
        )
        return (manager, dir, keychain)
    }

    /// Writes an encrypted database file the way an older version would have.
    private func writeLegacyDatabase(at url: URL, password: String, keyCount: Int) throws {
        var db = DuoDatabase()
        for i in 0..<keyCount {
            db.keys.append(DuoKey(name: "legacy-\(i)", secret: "AAAAAAAAAAAAAAAA", host: "api-test.duosecurity.com"))
        }
        let json = try JSONEncoder().encode(db)
        let encrypted = try CryptoService().encrypt(json, password: password)
        try encrypted.write(to: url)
    }

    @MainActor
    func testMigrationAdoptsTheDatabaseAndStoresThePassword() async throws {
        let (manager, dir, keychain) = try makeManager()
        let legacy = dir.appendingPathComponent("legacy-duo.db")
        try writeLegacyDatabase(at: legacy, password: "old-secret", keyCount: 3)

        try await manager.migrateDatabase(from: legacy, password: "old-secret")

        XCTAssertEqual(manager.database?.keys.count, 3)
        XCTAssertFalse(manager.isLocked)
        XCTAssertFalse(manager.showCreateDatabasePrompt)
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.databaseURL.path),
                      "the database should now exist at the app's own location")
        XCTAssertEqual(keychain.getPassword(), "old-secret",
                       "the migrated password becomes this install's password")
    }

    @MainActor
    func testWrongPasswordChangesNothing() async throws {
        let (manager, dir, keychain) = try makeManager()
        let legacy = dir.appendingPathComponent("legacy-duo.db")
        try writeLegacyDatabase(at: legacy, password: "old-secret", keyCount: 2)

        do {
            try await manager.migrateDatabase(from: legacy, password: "wrong")
            XCTFail("a wrong password must not migrate")
        } catch {
            // expected
        }

        XCTAssertNil(manager.database)
        XCTAssertFalse(FileManager.default.fileExists(atPath: manager.databaseURL.path),
                       "nothing may be written until the source decrypts")
        XCTAssertNil(keychain.getPassword(),
                     "a failed migration must not store a password")
    }

    @MainActor
    func testUnrelatedFileIsRejected() async throws {
        let (manager, dir, keychain) = try makeManager()
        let junk = dir.appendingPathComponent("not-a-database.bin")
        try Data("this is not an encrypted database".utf8).write(to: junk)

        do {
            try await manager.migrateDatabase(from: junk, password: "anything")
            XCTFail("an unrelated file must not migrate")
        } catch {
            // expected
        }

        XCTAssertNil(manager.database)
        XCTAssertFalse(FileManager.default.fileExists(atPath: manager.databaseURL.path))
        XCTAssertNil(keychain.getPassword())
    }

    @MainActor
    func testMissingSourceFileThrowsFileNotFound() async throws {
        let (manager, dir, _) = try makeManager()
        let absent = dir.appendingPathComponent("does-not-exist.db")

        do {
            try await manager.migrateDatabase(from: absent, password: "x")
            XCTFail("expected a failure for a missing source")
        } catch DatabaseError.fileNotFound {
            // expected
        }
    }
}
