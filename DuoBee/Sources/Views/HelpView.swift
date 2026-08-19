//
//  HelpView.swift
//  DuoBee
//
//  Created on 2026-01-04.
//  SPDX-License-Identifier: AGPL-3.0-or-later
//

import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("DuoBee Help")
                        .font(.largeTitle)
                        .bold()
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 10)

                Divider()

                helpSection(title: "Getting Started", content: """
                DuoBee is a native macOS authenticator that generates one-time passwords (OTP) for two-factor authentication.

                To get started:
                1. Create a new database with a secure password
                2. Add your first Duo key using the "Add New Key" button or Cmd+K
                3. Generate OTPs by selecting a key from the list
                """)

                helpSection(title: "Adding Keys", content: """
                You can add Duo keys in several ways:

                • Manual Entry: Enter the activation code and host name manually
                • QR Code: Scan a QR code containing duo:// URL
                • URL: Paste a duo:// URL directly

                The activation code format is typically shown as a series of characters separated by dashes.
                The host name is usually in the format: api-xxxxxxxx.duosecurity.com
                """)

                helpSection(title: "Database Security", content: """
                Your Duo keys are stored in an encrypted database using AES-GCM encryption.

                • Database location: ~/Library/Application Support/DuoBee/duo.db
                • Password stored securely in macOS Keychain
                • Lock database anytime with Cmd+Shift+L
                • Change password from Database menu or Settings
                """)

                helpSection(title: "Keyboard Shortcuts", content: """
                • Cmd+K - Add New Key
                • Cmd+, - Settings
                • Cmd+Shift+I - Import Database
                • Cmd+Shift+E - Export Database
                • Cmd+Shift+L - Lock Database
                • Cmd+? - Show Help
                """)

                helpSection(title: "Database Management", content: """
                Import/Export: Share your database across devices by exporting and importing the encrypted .db file. The same password must be used.

                Backup: Regularly export your database to a secure location as a backup.

                Delete All Keys: Removes all keys but keeps the database file.

                Delete Database: Completely removes the database file. This action cannot be undone.
                """)

                helpSection(title: "Troubleshooting", content: """
                OTP not working?
                • Ensure your system time is accurate (OTPs are time-based)
                • Verify the activation code and host name are correct
                • Try reactivating the key

                Can't unlock database?
                • If you've forgotten your password, you'll need to delete the database and start over
                • Always export your database as a backup

                Import fails?
                • Ensure you're using the correct password
                • Verify the file is a valid DuoBee database
                """)

                Divider()

                Text(AppVersion.displayString)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("License: GNU AGPL v3 or later")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom)
            }
            .padding()
        }
        .frame(width: 550, height: 550)
    }

    private func helpSection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(content)
                .font(.body)
                .foregroundColor(.primary)
        }
    }
}
