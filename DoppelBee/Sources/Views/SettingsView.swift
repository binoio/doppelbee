//
//  SettingsView.swift
//  DoppelBee
//
//  Created on 2026-01-04.
//  SPDX-License-Identifier: AGPL-3.0-or-later
//

import SwiftUI
import AppKit
import UserNotifications

struct SettingsView: View {
    /// nil when Sparkle is not running (previews, and the test host, which has
    /// no SUFeedURL); the Updates section is then omitted.
    var updaterViewModel: UpdaterViewModel?

    @EnvironmentObject var databaseManager: DuoDatabaseManager
    @State private var launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
    @State private var autoUnlock = UserDefaults.standard.bool(forKey: "autoUnlockOnLaunch")
    @State private var autoConfirmAllPushes = UserDefaults.standard.bool(forKey: "autoConfirmAllPushes")
    @State private var enableNotifications = UserDefaults.standard.object(forKey: "enableSystemNotifications") as? Bool ?? true
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showingChangePassword = false
    @State private var showingDeleteKeysConfirmation = false
    @State private var showingDeleteDatabaseConfirmation = false

    var body: some View {
        Form {
                Section(header: Text("General").font(.headline)) {
                    Toggle("Launch at Login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "launchAtLogin")
                            // TODO: Implement SMAppService integration
                        }

                    Divider()

                    Toggle("Auto-unlock Database on Launch", isOn: $autoUnlock)
                        .onChange(of: autoUnlock) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "autoUnlockOnLaunch")
                        }
                        .help("Automatically unlock the database using saved keychain password when launching the app")
                }

                if let updaterViewModel {
                    UpdatesSectionView(viewModel: updaterViewModel)
                }

                Section(header: Text("Duo Push").font(.headline)) {
                    Toggle("Auto-confirm Standard Pushes", isOn: $autoConfirmAllPushes)
                        .onChange(of: autoConfirmAllPushes) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "autoConfirmAllPushes")
                        }
                        .help("Automatically confirm standard Duo Push notifications without manual approval")

                    Text("Verified Duo Push is never auto-confirmed. Those requests always wait for you to enter the code shown on the device you are logging in from.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle("Enable System Notifications", isOn: $enableNotifications)
                        .onChange(of: enableNotifications) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "enableSystemNotifications")
                            if newValue && notificationStatus == .notDetermined {
                                requestNotificationPermission()
                            }
                        }
                        .help("Show actionable system notifications for incoming push requests")

                    if notificationStatus == .denied {
                        Text("⚠️ System notifications are disabled. Please enable them in macOS System Settings.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if notificationStatus == .notDetermined {
                        Button("Request Notification Permission") {
                            requestNotificationPermission()
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                }

                Section(header: Text("Database").font(.headline)) {
                    if let dbPath = databaseManager.databasePath {
                        HStack {
                            Text("Database Location:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(action: {
                                revealInFinder(dbPath)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "folder")
                                    Text(dbPath.path)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .frame(maxWidth: 200)
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.blue)
                            .help("Click to reveal in Finder")
                        }
                    }

                    Button("Change Database Password...") {
                        showingChangePassword = true
                    }
                    .disabled(databaseManager.database == nil)

                    Button("Delete All Keys") {
                        showingDeleteKeysConfirmation = true
                    }
                    .disabled(databaseManager.database == nil)
                    .foregroundColor(.red)

                    Button("Delete Database") {
                        showingDeleteDatabaseConfirmation = true
                    }
                    .disabled(databaseManager.database == nil)
                    .foregroundColor(.red)
                }
            }
            .formStyle(.grouped)
            .frame(width: 500, height: updaterViewModel == nil ? 620 : 740)
            .onAppear {
                checkNotificationStatus()
            }
        .sheet(isPresented: $showingChangePassword) {
            ChangePasswordView(isPresented: $showingChangePassword)
                .environmentObject(databaseManager)
        }
        .alert("Delete All Keys", isPresented: $showingDeleteKeysConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                deleteAllKeys()
            }
        } message: {
            Text("Are you sure you want to delete all keys? This action cannot be undone.")
        }
        .alert("Delete Database", isPresented: $showingDeleteDatabaseConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteDatabase()
            }
        } message: {
            Text("Are you sure you want to delete the entire database? This action cannot be undone and will require creating a new database.")
        }
    }

    private func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationStatus = settings.authorizationStatus
            }
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            checkNotificationStatus()
        }
    }

    private func deleteAllKeys() {
        do {
            try databaseManager.deleteAllKeys()
        } catch {
            databaseManager.errorMessage = "Failed to delete keys: \(error.localizedDescription)"
        }
    }

    private func deleteDatabase() {
        do {
            try databaseManager.deleteDatabase()
        } catch {
            databaseManager.errorMessage = "Failed to delete database: \(error.localizedDescription)"
        }
    }

    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
