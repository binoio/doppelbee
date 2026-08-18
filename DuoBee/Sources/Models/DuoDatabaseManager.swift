//
//  DuoDatabaseManager.swift
//  DuoBee
//
//  Created on 2026-01-04.
//  SPDX-License-Identifier: MIT
//

import Foundation
import SwiftUI

@MainActor
class DuoDatabaseManager: ObservableObject {
    @Published var database: DuoDatabase?
    @Published var isLocked = true
    @Published var showAddKeySheet = false
    @Published var showPasswordPrompt = false
    @Published var showCreateDatabasePrompt = false
    @Published var errorMessage: String?

    private let cryptoService = CryptoService()
    private let keychainService: KeychainService
    private let defaults: UserDefaults
    let databaseURL: URL

    /// Location of the real database in Application Support.
    /// `nonisolated` so it can be used as a default argument to `init`.
    nonisolated static func defaultDatabaseURL() -> URL {
        let containerURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = containerURL.appendingPathComponent("DuoBee", isDirectory: true)
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        return appFolder.appendingPathComponent("duo.db")
    }

    var databasePath: URL? {
        return FileManager.default.fileExists(atPath: databaseURL.path) ? databaseURL : nil
    }

    /// Dependencies are injectable so tests never touch the user's real database,
    /// keychain item, or preferences. `autoLoad` defers the initial unlock attempt,
    /// which is what makes a test instance inert until it is explicitly driven.
    init(
        databaseURL: URL = DuoDatabaseManager.defaultDatabaseURL(),
        keychainService: KeychainService = KeychainService(),
        defaults: UserDefaults = .standard,
        autoLoad: Bool = true
    ) {
        self.databaseURL = databaseURL
        self.keychainService = keychainService
        self.defaults = defaults

        if autoLoad {
            Task {
                await checkAndLoadDatabase()
            }
        }
    }

    func checkAndLoadDatabase() async {
        // Reset all state flags first
        showPasswordPrompt = false
        showCreateDatabasePrompt = false
        errorMessage = nil

        // Check if database file exists
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            // No database file - clean up any orphaned keychain entries and show create prompt
            keychainService.deletePassword()
            showCreateDatabasePrompt = true
            return
        }

        // Database exists - check if we should auto-unlock
        let autoUnlock = defaults.bool(forKey: "autoUnlockOnLaunch")

        if autoUnlock, let password = keychainService.getPassword() {
            // Try to auto-unlock with keychain password
            do {
                try await loadDatabase(password: password)
            } catch {
                // Auto-unlock failed - could be wrong password or corrupted database
                handleDatabaseLoadError(error)
            }
        } else {
            // No auto-unlock or no saved password - prompt for password
            showPasswordPrompt = true
        }
    }

    private func handleDatabaseLoadError(_ error: Error) {
        // Check if this is a decryption error (wrong password or corrupted database)
        if case CryptoError.decryptionFailed = error {
            errorMessage = "Failed to unlock database. The saved password may be incorrect or the database may be corrupted."
        } else {
            errorMessage = "Failed to unlock database: \(error.localizedDescription)"
        }
        showPasswordPrompt = true
    }

    func createDatabase(password: String) async throws {
        // Ensure we're starting fresh - clean up any orphaned keychain entries
        keychainService.deletePassword()

        // Create and save new database
        let newDatabase = DuoDatabase()
        try saveDatabase(newDatabase, password: password)

        // Save password to keychain
        keychainService.savePassword(password)

        // Update state
        database = newDatabase
        isLocked = false
        showCreateDatabasePrompt = false
        showPasswordPrompt = false
        errorMessage = nil
    }

    func loadDatabase(password: String) async throws {
        // Verify database file still exists
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            // Database was deleted after initial check - reset to create mode
            await checkAndLoadDatabase()
            throw DatabaseError.fileNotFound
        }

        // Try to read and decrypt the database
        let encryptedData = try Data(contentsOf: databaseURL)
        let decryptedData = try cryptoService.decrypt(encryptedData, password: password)

        // Parse the decrypted data
        let decoder = JSONDecoder()
        database = try decoder.decode(DuoDatabase.self, from: decryptedData)

        // Successfully loaded - update state
        isLocked = false
        showPasswordPrompt = false
        showCreateDatabasePrompt = false
        errorMessage = nil

        // Save the working password to keychain
        keychainService.savePassword(password)
    }

    func saveDatabase(_ db: DuoDatabase, password: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(db)

        let encryptedData = try cryptoService.encrypt(jsonData, password: password)
        try encryptedData.write(to: databaseURL)
    }

    func saveCurrentDatabase() throws {
        guard let db = database else {
            throw DatabaseError.noDatabaseLoaded
        }
        guard let password = keychainService.getPassword() else {
            throw DatabaseError.noPasswordAvailable
        }
        try saveDatabase(db, password: password)
    }

    func lockDatabase() {
        database = nil
        isLocked = true
    }

    func addKey(_ key: DuoKey) throws {
        guard var db = database else {
            throw DatabaseError.noDatabaseLoaded
        }
        db.addKey(key)
        database = db
        try saveCurrentDatabase()
    }

    func removeKey(withId id: UUID) throws {
        guard var db = database else {
            throw DatabaseError.noDatabaseLoaded
        }
        db.removeKey(withId: id)
        database = db
        try saveCurrentDatabase()
    }

    func updateKey(_ key: DuoKey) throws {
        guard var db = database else {
            throw DatabaseError.noDatabaseLoaded
        }
        db.updateKey(key)
        database = db
        try saveCurrentDatabase()
    }

    func moveKeys(from source: IndexSet, to destination: Int) throws {
        guard var db = database else {
            throw DatabaseError.noDatabaseLoaded
        }
        db.moveKeys(from: source, to: destination)
        database = db
        try saveCurrentDatabase()
    }

    func importDatabase(from url: URL) async throws {
        // Start accessing security-scoped resource
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // Read the database file
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DatabaseError.fileNotFound
        }

        guard let password = keychainService.getPassword() else {
            throw DatabaseError.noPasswordAvailable
        }

        // Try to decrypt and verify it's a valid database
        let encryptedData = try Data(contentsOf: url)
        let decryptedData = try cryptoService.decrypt(encryptedData, password: password)
        let decoder = JSONDecoder()
        let importedDatabase = try decoder.decode(DuoDatabase.self, from: decryptedData)

        // Copy to the app's database location
        try encryptedData.write(to: databaseURL)
        database = importedDatabase
    }

    func exportDatabase(to url: URL) throws {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw DatabaseError.fileNotFound
        }

        // Copy the database file to the destination
        try FileManager.default.copyItem(at: databaseURL, to: url)
    }

    func changePassword(oldPassword: String, newPassword: String) async throws {
        guard let db = database else {
            throw DatabaseError.noDatabaseLoaded
        }

        // Verify old password by trying to decrypt
        let encryptedData = try Data(contentsOf: databaseURL)
        _ = try cryptoService.decrypt(encryptedData, password: oldPassword)

        // Save with new password
        try saveDatabase(db, password: newPassword)
        keychainService.savePassword(newPassword)
    }

    func deleteAllKeys() throws {
        guard var db = database else {
            throw DatabaseError.noDatabaseLoaded
        }
        db.keys = []
        database = db
        try saveCurrentDatabase()
    }

    func deleteDatabase() throws {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw DatabaseError.fileNotFound
        }
        try FileManager.default.removeItem(at: databaseURL)
        keychainService.deletePassword()
        database = nil
        isLocked = true
        showPasswordPrompt = false
        showCreateDatabasePrompt = true
        errorMessage = nil
    }

    /// Re-check database state - useful when recovering from errors or after external changes
    func recheckDatabaseState() {
        Task {
            await checkAndLoadDatabase()
        }
    }
}

enum DatabaseError: LocalizedError {
    case fileNotFound
    case noDatabaseLoaded
    case noPasswordAvailable
    case invalidPassword

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Database file not found"
        case .noDatabaseLoaded:
            return "No database is currently loaded"
        case .noPasswordAvailable:
            return "No password available"
        case .invalidPassword:
            return "Invalid password"
        }
    }
}
