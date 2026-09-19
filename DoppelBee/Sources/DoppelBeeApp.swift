//
//  DoppelBeeApp.swift
//  DoppelBee
//
//  Created on 2026-01-04.
//  SPDX-License-Identifier: AGPL-3.0-or-later
//

import SwiftUI
import AppKit
import Sparkle

@main
struct DoppelBeeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var databaseManager: DuoDatabaseManager
    @StateObject private var pushService: DuoPushService
    @State private var showingChangePassword = false
    @State private var showingImportPicker = false
    @State private var showingExportPicker = false

    init() {
        let dbManager = DuoDatabaseManager()
        let pushSvc = DuoPushService()
        
        pushSvc.observeDatabase(dbManager)
        
        self._databaseManager = StateObject(wrappedValue: dbManager)
        self._pushService = StateObject(wrappedValue: pushSvc)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(databaseManager)
                .environmentObject(pushService)
                .frame(minWidth: 600, minHeight: 400)
                .sheet(isPresented: $showingChangePassword) {
                    ChangePasswordView(isPresented: $showingChangePassword)
                        .environmentObject(databaseManager)
                }
                .fileImporter(isPresented: $showingImportPicker, allowedContentTypes: [.data]) { result in
                    handleImport(result)
                }
                .onChange(of: showingExportPicker) { _, newValue in
                    if newValue {
                        showExportPanel()
                    }
                }
        }

        // commandsRemoved() drops the Window-menu items these scenes would
        // otherwise auto-register; they are opened from the app and Help
        // menus via the command groups below.
        Window("DoppelBee Help", id: "help") {
            HelpView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commandsRemoved()

        Window("About DoppelBee", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .windowStyle(.hiddenTitleBar)
        .commandsRemoved()

        Settings {
            SettingsView(updaterViewModel: appDelegate.updaterViewModel)
                .environmentObject(databaseManager)
        }

        .commands {
            CommandGroup(replacing: .appInfo) {
                AboutCommand()

                Divider()

                CheckForUpdatesView(viewModel: appDelegate.updaterViewModel)
            }

            CommandMenu("Database") {
                Button("Add New Key") {
                    databaseManager.showAddKeySheet = true
                }
                .keyboardShortcut("k", modifiers: .command)

                Divider()

                Button("Change Password...") {
                    showingChangePassword = true
                }
                .disabled(databaseManager.database == nil)

                Button("Import Database...") {
                    showingImportPicker = true
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(databaseManager.database == nil)

                Button("Export Database...") {
                    showingExportPicker = true
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(databaseManager.database == nil)

                Divider()

                Button("Lock Database") {
                    databaseManager.lockDatabase()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(databaseManager.database == nil)
            }

            CommandMenu("Key") {
                GenerateTokenCommand()
                CopyTokenCommand()
                Divider()
                DeleteKeyCommand()
            }

            CommandGroup(replacing: .help) {
                HelpCommand()
            }
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            Task {
                do {
                    try await databaseManager.importDatabase(from: url)
                } catch {
                    await MainActor.run {
                        databaseManager.errorMessage = "Failed to import database: \(error.localizedDescription)"
                    }
                }
            }
        case .failure(let error):
            databaseManager.errorMessage = "Failed to select file: \(error.localizedDescription)"
        }
    }

    private func showExportPanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.data]
        panel.nameFieldStringValue = "duo.db"
        panel.message = "Export Database"
        panel.prompt = "Export"

        panel.begin { response in
            showingExportPicker = false
            if response == .OK, let url = panel.url {
                do {
                    try databaseManager.exportDatabase(to: url)
                } catch {
                    databaseManager.errorMessage = "Failed to export database: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Command Wrappers

struct HelpCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("DoppelBee Help") {
            openWindow(id: "help")
        }
        .keyboardShortcut("?", modifiers: .command)
    }
}

struct AboutCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About DoppelBee") {
            openWindow(id: "about")
        }
    }
}

struct GenerateTokenCommand: View {
    @FocusedValue(\.selectedKey) var selectedKey
    @FocusedValue(\.generateTokenAction) var generateAction

    var body: some View {
        Button("Generate New Token") {
            generateAction?()
        }
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(selectedKey == nil)
    }
}

struct CopyTokenCommand: View {
    @FocusedValue(\.hasGeneratedCode) var hasCode
    @FocusedValue(\.copyTokenAction) var copyAction

    var body: some View {
        Button("Copy Token") {
            copyAction?()
        }
        .keyboardShortcut("c", modifiers: .command)
        .disabled(hasCode != true)
    }
}

struct DeleteKeyCommand: View {
    @FocusedValue(\.selectedKey) var selectedKey
    @FocusedValue(\.deleteKeyAction) var deleteAction

    var body: some View {
        Button("Delete Key") {
            deleteAction?()
        }
        .keyboardShortcut(.delete, modifiers: .command)
        .disabled(selectedKey == nil)
    }
}

// MARK: - AppDelegate
class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    lazy var updaterViewModel = UpdaterViewModel(updater: updaterController.updater)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Tests are app-hosted, so Bundle.main is DoppelBee.app and SUFeedURL is
        // present — checking for the key alone would still start the updater
        // under `xcodebuild test`. XCTest's environment is the reliable signal.
        let runningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let hasFeed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        if hasFeed && !runningTests {
            updaterController.startUpdater()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
