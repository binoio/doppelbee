//
//  ContentView.swift
//  DuoBee
//
//  Created on 2026-01-04.
//  SPDX-License-Identifier: MIT
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var databaseManager: DuoDatabaseManager
    @EnvironmentObject var pushService: DuoPushService
    @State private var selectedKeyId: UUID?
    @State private var showingAddKey = false
    @State private var showingRenameKey = false
    @State private var showingDeleteConfirmation = false
    @State private var showingChangePassword = false
    @State private var showingKeySettings = false
    @State private var keyToRename: DuoKey?
    @State private var keyToDelete: DuoKey?
    @State private var keyForSettings: DuoKey?
    @State private var newKeyName = ""
    @State private var generatedCode: String?
    @State private var copiedKeyId: UUID?

    var body: some View {
        VStack {
            if databaseManager.showCreateDatabasePrompt {
                CreateDatabaseView()
            } else if databaseManager.showPasswordPrompt {
                UnlockDatabaseView()
            } else if let database = databaseManager.database {
                mainView(database: database)
            } else {
                ProgressView("Loading...")
            }
        }
        .sheet(isPresented: $showingAddKey) {
            AddKeyView(isPresented: $showingAddKey)
        }
        .sheet(isPresented: $showingChangePassword) {
            ChangePasswordView(isPresented: $showingChangePassword)
        }
        .sheet(isPresented: $showingKeySettings) {
            if let key = keyForSettings {
                KeySettingsView(key: key, isPresented: $showingKeySettings)
            }
        }
        .alert("Rename Key", isPresented: $showingRenameKey) {
            TextField("New name", text: $newKeyName)
            Button("Cancel", role: .cancel) {
                keyToRename = nil
                newKeyName = ""
            }
            Button("Rename") {
                if let key = keyToRename {
                    performRename(key)
                }
            }
        } message: {
            Text("Enter a new name for this key")
        }
        .alert("Delete Key", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                keyToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let key = keyToDelete {
                    performDelete(key)
                }
            }
        } message: {
            if let key = keyToDelete {
                Text("Are you sure you want to delete '\(key.name)'? This action cannot be undone.")
            }
        }
        .alert("Error", isPresented: .constant(databaseManager.errorMessage != nil)) {
            Button("OK") {
                databaseManager.errorMessage = nil
            }
        } message: {
            if let error = databaseManager.errorMessage {
                Text(error)
            }
        }
    }

    @ViewBuilder
    private func mainView(database: DuoDatabase) -> some View {
        VStack(spacing: 0) {
            // Header with Add button
            HStack {
                Text("Duo Keys")
                    .font(.title2)
                    .bold()
                Spacer()
                Button(action: { showingAddKey = true }) {
                    Label("Add New Key", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            // Pending push notifications
            if !pushService.pendingPushes.isEmpty {
                pendingPushesView
                Divider()
            }

            // Keys list
            if database.keys.isEmpty {
                emptyStateView
            } else {
                keysListView(keys: database.keys)
            }
        }
    }

    private var pendingPushesView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(pushService.pendingPushes.keys), id: \.self) { keyIdString in
                if let keyId = UUID(uuidString: keyIdString),
                   let pushes = pushService.pendingPushes[keyIdString],
                   let key = databaseManager.database?.keys.first(where: { $0.id == keyId }) {
                    ForEach(pushes, id: \.urgid) { push in
                        PushNotificationView(
                            keyName: key.name,
                            push: push,
                            onApprove: { stepUpCode in
                                Task {
                                    do {
                                        try await pushService.approvePush(keyId: keyId, urgid: push.urgid, stepUpCode: stepUpCode)
                                    } catch {
                                        databaseManager.errorMessage = "Failed to approve push: \(error.localizedDescription)"
                                    }
                                }
                            },
                            onDeny: {
                                Task {
                                    do {
                                        try await pushService.denyPush(keyId: keyId, urgid: push.urgid)
                                    } catch {
                                        databaseManager.errorMessage = "Failed to deny push: \(error.localizedDescription)"
                                    }
                                }
                            },
                            onDismiss: {
                                pushService.dismissPush(keyId: keyId, urgid: push.urgid)
                            }
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color.accentColor.opacity(0.1))
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 64))
                .foregroundColor(.gray)
            Text("No Duo Keys")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Add your first Duo key to get started")
                .foregroundColor(.secondary)
            Button(action: { showingAddKey = true }) {
                Label("Add New Key", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func keysListView(keys: [DuoKey]) -> some View {
        List(selection: $selectedKeyId) {
            ForEach(keys) { key in
                KeyRowView(
                    key: key,
                    isSelected: selectedKeyId == key.id,
                    generatedCode: selectedKeyId == key.id ? generatedCode : nil,
                    showCopied: copiedKeyId == key.id,
                    onGenerate: { generateCode(for: key) },
                    onCopy: { copyCode(for: key) },
                    onRename: { renameKey(key) },
                    onDelete: { deleteKey(key) },
                    onSettings: { showKeySettings(key) }
                )
                .tag(key.id)
            }
            .onMove(perform: moveKeys)
        }
        .listStyle(.inset)
        .onDeleteCommand {
            if let keyId = selectedKeyId,
               let key = keys.first(where: { $0.id == keyId }) {
                deleteKey(key)
            }
        }
        .focusedSceneValue(\.selectedKey, selectedKey(from: keys))
        .focusedSceneValue(\.generateTokenAction) {
            if let keyId = selectedKeyId,
               let key = keys.first(where: { $0.id == keyId }) {
                generateCode(for: key)
            }
        }
        .focusedSceneValue(\.copyTokenAction) {
            if let keyId = selectedKeyId,
               let key = keys.first(where: { $0.id == keyId }) {
                copyCode(for: key)
            }
        }
        .focusedSceneValue(\.deleteKeyAction) {
            if let keyId = selectedKeyId,
               let key = keys.first(where: { $0.id == keyId }) {
                deleteKey(key)
            }
        }
        .focusedSceneValue(\.hasGeneratedCode, generatedCode != nil && selectedKeyId != nil)
    }

    private func selectedKey(from keys: [DuoKey]) -> DuoKey? {
        guard let keyId = selectedKeyId else { return nil }
        return keys.first(where: { $0.id == keyId })
    }

    private func moveKeys(from source: IndexSet, to destination: Int) {
        do {
            try databaseManager.moveKeys(from: source, to: destination)
        } catch {
            databaseManager.errorMessage = "Failed to reorder keys: \(error.localizedDescription)"
        }
    }

    private func generateCode(for key: DuoKey) {
        var updatedKey = key
        updatedKey.incrementCounter()

        do {
            let generator = HOTPGenerator()
            let code = try generator.generate(secret: key.secret, counter: updatedKey.counter)
            generatedCode = code
            selectedKeyId = key.id
            try databaseManager.updateKey(updatedKey)
        } catch {
            databaseManager.errorMessage = "Failed to generate code: \(error.localizedDescription)"
        }
    }

    private func copyCode(for key: DuoKey) {
        if let code = generatedCode, selectedKeyId == key.id {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
            copiedKeyId = key.id

            // Reset copied state after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if copiedKeyId == key.id {
                    copiedKeyId = nil
                }
            }
        }
    }

    private func renameKey(_ key: DuoKey) {
        keyToRename = key
        newKeyName = key.name
        showingRenameKey = true
    }

    private func showKeySettings(_ key: DuoKey) {
        keyForSettings = key
        showingKeySettings = true
    }

    private func performRename(_ key: DuoKey) {
        guard !newKeyName.isEmpty else { return }

        var updatedKey = key
        updatedKey.name = newKeyName

        do {
            try databaseManager.updateKey(updatedKey)
            keyToRename = nil
            newKeyName = ""
        } catch {
            databaseManager.errorMessage = "Failed to rename key: \(error.localizedDescription)"
        }
    }

    private func deleteKey(_ key: DuoKey) {
        keyToDelete = key
        showingDeleteConfirmation = true
    }

    private func performDelete(_ key: DuoKey) {
        do {
            try databaseManager.removeKey(withId: key.id)
            keyToDelete = nil

            // Clear selection if deleted key was selected
            if selectedKeyId == key.id {
                selectedKeyId = nil
                generatedCode = nil
            }
        } catch {
            databaseManager.errorMessage = "Failed to delete key: \(error.localizedDescription)"
        }
    }
}

struct KeyRowView: View {
    let key: DuoKey
    let isSelected: Bool
    let generatedCode: String?
    let showCopied: Bool
    let onGenerate: () -> Void
    let onCopy: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(key.name)
                    .font(.headline)
                Text(key.host)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let code = generatedCode, isSelected {
                Button(action: onCopy) {
                    Text(code)
                        .font(.system(.title3, design: .monospaced))
                        .bold()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(showCopied ? Color.green.opacity(0.2) : Color.accentColor.opacity(0.1))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .help("Click to copy")
            }

            HStack(spacing: 8) {
                Button(action: onGenerate) {
                    Label("Generate", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Generate new code")

                if generatedCode != nil && isSelected {
                    Button(action: onCopy) {
                        Label(showCopied ? "Copied" : "Copy", systemImage: showCopied ? "checkmark" : "doc.on.doc")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("Copy to clipboard")
                }

                Menu {
                    Button("Rename", action: onRename)
                    if key.pkey != nil && key.akey != nil {
                        Button("Settings", action: onSettings)
                    }
                    Divider()
                    Button("Delete", role: .destructive, action: onDelete)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                }
                .menuStyle(.borderlessButton)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

struct PushNotificationView: View {
    let keyName: String
    let push: DuoAPIService.PushTransaction
    let onApprove: (String?) -> Void
    let onDeny: () -> Void
    let onDismiss: () -> Void

    @State private var verificationCode = ""

    private var expectedDigits: Int {
        push.stepUpNumDigits ?? 0
    }

    private var isCodeValid: Bool {
        verificationCode.count == expectedDigits
            && verificationCode.allSatisfy { $0.isASCII && $0.isNumber }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: push.isVerifiedPush ? "lock.badge.clock.fill" : "bell.badge.fill")
                .font(.title2)
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text(push.displayTitle)
                    .font(.headline)
                Text("For: \(keyName)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let message = push.message {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Request details (who, where, when). Shown so an unexpected push
                // is recognisable before it is approved.
                if !push.attributes.isEmpty {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(push.attributes, id: \.self) { attribute in
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("\(attribute.label):")
                                    .foregroundColor(.secondary)
                                Text(attribute.value)
                                    .textSelection(.enabled)
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.top, 2)
                }

                if push.isVerifiedPush {
                    Text("Verified Duo Push — enter the \(expectedDigits)-digit code shown on the device you are logging in from.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if push.isVerifiedPush {
                    TextField("Code", text: $verificationCode)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 90)
                        .onSubmit {
                            if isCodeValid { onApprove(verificationCode) }
                        }
                        .onChange(of: verificationCode) { _, newValue in
                            // Codes are numeric and fixed-length; keep the field honest.
                            let digits = newValue.filter { $0.isASCII && $0.isNumber }
                            verificationCode = String(digits.prefix(expectedDigits))
                        }
                }

                Button("Deny") {
                    onDeny()
                }
                .buttonStyle(.bordered)

                Button("Approve") {
                    onApprove(push.isVerifiedPush ? verificationCode : nil)
                }
                .buttonStyle(.borderedProminent)
                .disabled(push.isVerifiedPush && !isCodeValid)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Dismiss notification")
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct KeySettingsView: View {
    @EnvironmentObject var databaseManager: DuoDatabaseManager
    let key: DuoKey
    @Binding var isPresented: Bool
    @State private var autoConfirmPush: Bool

    init(key: DuoKey, isPresented: Binding<Bool>) {
        self.key = key
        self._isPresented = isPresented
        self._autoConfirmPush = State(initialValue: key.autoConfirmPush)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Key Settings")
                .font(.title)
                .bold()

            VStack(alignment: .leading, spacing: 12) {
                Text(key.name)
                    .font(.headline)
                Text(key.host)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Auto-confirm Duo Push for this key", isOn: $autoConfirmPush)
                    .help("Automatically approve standard Duo Push notifications for this specific key")

                Text("When enabled, standard push notifications for this key will be automatically approved without requiring manual confirmation.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Label("Verified Duo Push is never auto-confirmed. Those requests always wait for you to enter the code shown on the device you are logging in from.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)

                Button("Save") {
                    saveSettings()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(30)
        .frame(width: 450, height: 300)
    }

    private func saveSettings() {
        var updatedKey = key
        updatedKey.autoConfirmPush = autoConfirmPush

        do {
            try databaseManager.updateKey(updatedKey)
            isPresented = false
        } catch {
            databaseManager.errorMessage = "Failed to update key settings: \(error.localizedDescription)"
        }
    }
}

struct CreateDatabaseView: View {
    @EnvironmentObject var databaseManager: DuoDatabaseManager
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isCreating = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("Create Duo Database")
                .font(.title)
                .bold()

            Text("Set a password to protect your Duo keys")
                .foregroundColor(.secondary)

            VStack(spacing: 12) {
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)

                SecureField("Confirm Password", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
            }

            Button(action: createDatabase) {
                if isCreating {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 120)
                } else {
                    Text("Create Database")
                        .frame(width: 120)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(password.isEmpty || password != confirmPassword || isCreating)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func createDatabase() {
        guard password == confirmPassword else { return }

        isCreating = true
        Task {
            do {
                try await databaseManager.createDatabase(password: password)
            } catch {
                await MainActor.run {
                    databaseManager.errorMessage = "Failed to create database: \(error.localizedDescription)"
                    isCreating = false
                }
            }
        }
    }
}

struct UnlockDatabaseView: View {
    @EnvironmentObject var databaseManager: DuoDatabaseManager
    @State private var password = ""
    @State private var isUnlocking = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("Unlock Database")
                .font(.title)
                .bold()

            Text("Enter your database password")
                .foregroundColor(.secondary)

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .onSubmit(unlockDatabase)

            Button(action: unlockDatabase) {
                if isUnlocking {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 100)
                } else {
                    Text("Unlock")
                        .frame(width: 100)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(password.isEmpty || isUnlocking)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func unlockDatabase() {
        guard !password.isEmpty else { return }

        isUnlocking = true
        Task {
            do {
                try await databaseManager.loadDatabase(password: password)
            } catch DatabaseError.fileNotFound {
                // Database was deleted - state will be updated automatically by loadDatabase
                await MainActor.run {
                    isUnlocking = false
                    password = ""
                }
            } catch {
                await MainActor.run {
                    databaseManager.errorMessage = "Failed to unlock database: \(error.localizedDescription)"
                    isUnlocking = false
                    password = ""
                }
            }
        }
    }
}

struct AddKeyView: View {
    @EnvironmentObject var databaseManager: DuoDatabaseManager
    @Binding var isPresented: Bool
    @State private var activationURL = ""
    @State private var keyName = ""
    @State private var isActivating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Duo Key")
                .font(.title)
                .bold()

            VStack(alignment: .leading, spacing: 8) {
                Text("Activation URL")
                    .font(.headline)
                TextField("https://m-xxx.duosecurity.com/activate/xxx", text: $activationURL)
                    .textFieldStyle(.roundedBorder)
                Text("Paste the activation URL from Duo")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Key Name (optional)")
                    .font(.headline)
                TextField("My Duo Key", text: $keyName)
                    .textFieldStyle(.roundedBorder)
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)

                Button(action: activateKey) {
                    if isActivating {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 80)
                    } else {
                        Text("Activate")
                            .frame(width: 80)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(activationURL.isEmpty || isActivating)
            }
        }
        .padding(30)
        .frame(width: 500)
    }

    private func activateKey() {
        errorMessage = nil
        isActivating = true

        Task {
            do {
                let apiService = DuoAPIService()
                guard let (host, code) = apiService.parseActivationURL(activationURL) else {
                    throw DuoAPIError.invalidURL
                }

                let result = try await apiService.activate(host: host, code: code)

                let name = keyName.isEmpty ? result.name : keyName
                let key = DuoKey(
                    name: name,
                    secret: result.secret,
                    host: result.host,
                    publicKey: result.publicKey,
                    privateKey: result.privateKey,
                    pkey: result.pkey,
                    akey: result.akey
                )

                try databaseManager.addKey(key)

                await MainActor.run {
                    isPresented = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isActivating = false
                }
            }
        }
    }
}

// MARK: - Focused Values for Keyboard Shortcuts

struct SelectedKeyKey: FocusedValueKey {
    typealias Value = DuoKey
}

struct GenerateTokenActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct CopyTokenActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct DeleteKeyActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct HasGeneratedCodeKey: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    var selectedKey: DuoKey? {
        get { self[SelectedKeyKey.self] }
        set { self[SelectedKeyKey.self] = newValue }
    }

    var generateTokenAction: (() -> Void)? {
        get { self[GenerateTokenActionKey.self] }
        set { self[GenerateTokenActionKey.self] = newValue }
    }

    var copyTokenAction: (() -> Void)? {
        get { self[CopyTokenActionKey.self] }
        set { self[CopyTokenActionKey.self] = newValue }
    }

    var deleteKeyAction: (() -> Void)? {
        get { self[DeleteKeyActionKey.self] }
        set { self[DeleteKeyActionKey.self] = newValue }
    }

    var hasGeneratedCode: Bool? {
        get { self[HasGeneratedCodeKey.self] }
        set { self[HasGeneratedCodeKey.self] = newValue }
    }
}

#Preview {
    // A bare DuoDatabaseManager() would auto-unlock the real database, so rendering
    // this preview in Xcode would decrypt the user's keys. Keep the preview inert.
    ContentView()
        .environmentObject(DuoDatabaseManager(
            databaseURL: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("DuoBeePreview.db"),
            autoLoad: false
        ))
        .environmentObject(DuoPushService())
}
