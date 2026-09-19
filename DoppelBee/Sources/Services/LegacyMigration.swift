//
//  LegacyMigration.swift
//  DoppelBee
//
//  Created on 2026-09-19.
//  SPDX-License-Identifier: AGPL-3.0-or-later
//

import Foundation

/// Locates databases left behind by the app's earlier identities.
///
/// The app is sandboxed, so it cannot read — or even `stat` — another app's
/// container. That means a migration can never be automatic: nothing here
/// detects whether an old database exists. All this type does is build the
/// paths so an `NSOpenPanel` can be *pointed* at them. The panel runs out of
/// process in the powerbox, which can navigate where this app cannot, and the
/// user's selection is what grants read access to the chosen file.
enum LegacyMigration {

    /// A previous identity of this app, newest first.
    struct Origin {
        let bundleIdentifier: String
        /// The Application Support folder name used inside that container.
        let appFolder: String
        /// What to call it in the UI.
        let displayName: String

        var databaseURL: URL {
            LegacyMigration.realHomeDirectory
                .appendingPathComponent("Library/Containers", isDirectory: true)
                .appendingPathComponent(bundleIdentifier, isDirectory: true)
                .appendingPathComponent("Data/Library/Application Support", isDirectory: true)
                .appendingPathComponent(appFolder, isDirectory: true)
                .appendingPathComponent("duo.db")
        }

        var containerURL: URL {
            databaseURL.deletingLastPathComponent()
        }
    }

    /// Every identity this app has shipped under, newest first. 2.x used
    /// `io.bino.duobee`; 1.x shipped under an institutional namespace that
    /// 2.0.0 moved away from. Both are worth offering — a user upgrading
    /// from 1.x never had a 2.x container to migrate from.
    static let origins: [Origin] = [
        Origin(bundleIdentifier: "io.bino.duobee",
               appFolder: "DuoBee",
               displayName: "DuoBee 2.x"),
        Origin(bundleIdentifier: "edu.princeton.orfe.duobee",
               appFolder: "DuoBee",
               displayName: "DuoBee 1.x"),
    ]

    /// Where the open panel should start. The sandbox blocks us from checking
    /// which of these exists, so this is a best guess: the newest identity.
    /// If the folder is not there the panel just opens at its default.
    static var suggestedDirectory: URL {
        origins[0].containerURL
    }

    /// `NSHomeDirectory()` and `FileManager.homeDirectoryForCurrentUser` both
    /// return the *container* home inside a sandbox, which is not where other
    /// apps' containers live. The passwd entry is the real one.
    static var realHomeDirectory: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}
