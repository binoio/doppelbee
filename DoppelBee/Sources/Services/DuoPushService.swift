//
//  DuoPushService.swift
//  DoppelBee
//
//  Created on 2026-01-04.
//  SPDX-License-Identifier: AGPL-3.0-or-later
//

import Foundation
import Combine
import UserNotifications
import AppKit

protocol DuoPushAPIServiceProtocol {
    func checkForPushRequests(key: DuoKey) async throws -> [DuoAPIService.PushTransaction]
    func respondToPush(key: DuoKey, urgid: String, approve: Bool, stepUpCode: String?) async throws
}

extension DuoAPIService: DuoPushAPIServiceProtocol {}

@MainActor
class DuoPushService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var pendingPushes: [String: [DuoAPIService.PushTransaction]] = [:]

    private let apiService: DuoPushAPIServiceProtocol
    private let defaults: UserDefaults
    private var pollingTask: Task<Void, Never>?
    private var keys: [DuoKey] = []
    private var notifiedUrgids = Set<String>()
    private var cancellables = Set<AnyCancellable>()
    private var launchObserver: NSObjectProtocol?

    /// `defaults` is injectable so tests can set auto-confirm and notification
    /// preferences without mutating the user's real settings.
    init(apiService: DuoPushAPIServiceProtocol = DuoAPIService(), defaults: UserDefaults = .standard) {
        self.apiService = apiService
        self.defaults = defaults
        super.init()
        setupNotifications()
    }

    func observeDatabase(_ databaseManager: DuoDatabaseManager) {
        databaseManager.$database
            .receive(on: RunLoop.main)
            .sink { [weak self] database in
                guard let self = self else { return }
                if let keys = database?.keys {
                    self.startPolling(keys: keys)
                } else {
                    self.stopPolling()
                }
            }
            .store(in: &cancellables)
    }

    private func setupNotifications() {
        UNUserNotificationCenter.current().delegate = self

        // Registering categories or requesting authorization before the app has
        // finished launching silently does nothing on macOS — the app never appears
        // in Notification Center at all, so no push notification is ever delivered.
        // This service is constructed from DoppelBeeApp.init(), which runs before
        // NSApplication finishes launching, so defer until it has.
        if NSApp?.isRunning == true {
            registerForNotifications()
        } else {
            launchObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didFinishLaunchingNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.registerForNotifications()
                }
            }
        }
    }

    /// Registers notification categories and requests authorization. Must run after
    /// the app has finished launching.
    func registerForNotifications() {
        if let launchObserver = launchObserver {
            NotificationCenter.default.removeObserver(launchObserver)
            self.launchObserver = nil
        }

        let center = UNUserNotificationCenter.current()

        // Define Actionable Categories
        let approveAction = UNNotificationAction(
            identifier: "APPROVE_ACTION",
            title: "Approve",
            options: [] // Run in background
        )
        let denyAction = UNNotificationAction(
            identifier: "DENY_ACTION",
            title: "Deny",
            options: [.destructive] // Run in background, destructive style
        )
        let category = UNNotificationCategory(
            identifier: "DUO_PUSH_CATEGORY",
            actions: [approveAction, denyAction],
            intentIdentifiers: [],
            options: []
        )

        // Verified Duo Push cannot be approved with a single tap — the user has to
        // supply the code from the access device — so it gets a text-entry action
        // instead of a plain Approve button.
        let enterCodeAction = UNTextInputNotificationAction(
            identifier: "VERIFY_ACTION",
            title: "Enter Code",
            options: [],
            textInputButtonTitle: "Approve",
            textInputPlaceholder: "Verification code"
        )
        let verifiedCategory = UNNotificationCategory(
            identifier: "DUO_VERIFIED_PUSH_CATEGORY",
            actions: [enterCodeAction, denyAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([category, verifiedCategory])

        requestNotificationPermission()
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Error requesting notification permission: \(error.localizedDescription)")
            }
        }
    }

    func startPolling(keys: [DuoKey]) {
        self.keys = keys

        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                await checkAllKeys()
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // For testing: set keys without starting polling
    func setKeys(_ keys: [DuoKey]) {
        self.keys = keys
    }

    private func checkAllKeys() async {
        var activeUrgids = Set<String>()

        for key in keys {
            guard key.pkey != nil, key.akey != nil else { continue }

            do {
                let transactions = try await apiService.checkForPushRequests(key: key)

                if !transactions.isEmpty {
                    // Collect active transaction urgids
                    for tx in transactions {
                        activeUrgids.insert(tx.urgid)
                    }

                    // Auto-confirm if enabled. Verified Duo Push is deliberately
                    // excluded: the factor exists so a human reads a code off the
                    // access device, and approving one unattended would defeat it.
                    // Those always fall through to manual confirmation.
                    let globalAutoConfirm = defaults.bool(forKey: "autoConfirmAllPushes")
                    let autoConfirmEnabled = globalAutoConfirm || key.autoConfirmPush

                    let autoConfirmable = autoConfirmEnabled ? transactions.filter { !$0.isVerifiedPush } : []
                    let needsUser = autoConfirmEnabled ? transactions.filter { $0.isVerifiedPush } : transactions

                    for tx in autoConfirmable {
                        try? await apiService.respondToPush(key: key, urgid: tx.urgid, approve: true, stepUpCode: nil)
                    }

                    if needsUser.isEmpty {
                        pendingPushes[key.id.uuidString] = nil
                    } else {
                        // Find any new transactions to notify
                        let existingUrgids = Set(pendingPushes[key.id.uuidString]?.map { $0.urgid } ?? [])
                        pendingPushes[key.id.uuidString] = needsUser

                        for tx in needsUser {
                            if !existingUrgids.contains(tx.urgid) && !notifiedUrgids.contains(tx.urgid) {
                                notifiedUrgids.insert(tx.urgid)

                                let enableNotifications = defaults.object(forKey: "enableSystemNotifications") as? Bool ?? true
                                if enableNotifications {
                                    postLocalNotification(for: tx, key: key)
                                }
                            }
                        }
                    }
                } else {
                    pendingPushes[key.id.uuidString] = nil
                }
            } catch {
                // Silently fail - don't spam errors for polling
                continue
            }
        }

        // Keep only active transaction IDs in notifiedUrgids
        notifiedUrgids.formIntersection(activeUrgids)
    }

    private func postLocalNotification(for tx: DuoAPIService.PushTransaction, key: DuoKey) {
        let content = UNMutableNotificationContent()
        content.title = tx.displayTitle
        content.subtitle = "For: \(key.name)"
        content.sound = UNNotificationSound.default

        // Who and where, so an unexpected push is recognisable as such.
        let context = tx.message ?? tx.contextLine

        if tx.isVerifiedPush {
            let digits = tx.stepUpNumDigits ?? 0
            let prompt = "Enter the \(digits)-digit code shown on the device you are logging in from."
            content.body = [context, prompt].compactMap { $0 }.joined(separator: "\n")
            content.categoryIdentifier = "DUO_VERIFIED_PUSH_CATEGORY"
        } else {
            content.body = context ?? "Approve login request"
            content.categoryIdentifier = "DUO_PUSH_CATEGORY"
        }

        content.userInfo = [
            "keyId": key.id.uuidString,
            "urgid": tx.urgid
        ]

        let request = UNNotificationRequest(
            identifier: tx.urgid,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error posting system notification: \(error.localizedDescription)")
            }
        }
    }

    /// Look up a pending transaction so callers can tell whether it needs a
    /// verification code before it can be approved.
    func pendingTransaction(keyId: UUID, urgid: String) -> DuoAPIService.PushTransaction? {
        pendingPushes[keyId.uuidString]?.first(where: { $0.urgid == urgid })
    }

    func approvePush(keyId: UUID, urgid: String, stepUpCode: String? = nil) async throws {
        guard let key = keys.first(where: { $0.id == keyId }) else { return }

        let code = stepUpCode?.trimmingCharacters(in: .whitespacesAndNewlines)

        // Verified Duo Push must carry a well-formed code. Reject locally rather
        // than burning the transaction on a request Duo will refuse anyway.
        if let tx = pendingTransaction(keyId: keyId, urgid: urgid), tx.isVerifiedPush {
            let expectedDigits = tx.stepUpNumDigits ?? 0
            guard let code = code,
                  code.count == expectedDigits,
                  code.allSatisfy({ $0.isASCII && $0.isNumber }) else {
                throw DuoAPIError.invalidStepUpCode(expectedDigits: expectedDigits)
            }
        }

        // Attempt API call first
        try await apiService.respondToPush(
            key: key,
            urgid: urgid,
            approve: true,
            stepUpCode: (code?.isEmpty == false) ? code : nil
        )

        // Only remove from pending if API call succeeded
        removePushFromPending(keyId: keyId, urgid: urgid)
    }

    func denyPush(keyId: UUID, urgid: String) async throws {
        guard let key = keys.first(where: { $0.id == keyId }) else { return }

        // Attempt API call first
        try await apiService.respondToPush(key: key, urgid: urgid, approve: false, stepUpCode: nil)

        // Only remove from pending if API call succeeded
        removePushFromPending(keyId: keyId, urgid: urgid)
    }

    private func removePushFromPending(keyId: UUID, urgid: String) {
        if var pushes = pendingPushes[keyId.uuidString] {
            pushes.removeAll { $0.urgid == urgid }
            pendingPushes[keyId.uuidString] = pushes.isEmpty ? nil : pushes
        }
        
        // Remove from delivered notifications to dismiss the banner
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [urgid])
    }

    func dismissPush(keyId: UUID, urgid: String) {
        // Remove from pending without calling API
        removePushFromPending(keyId: keyId, urgid: urgid)
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionIdentifier = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo

        guard let keyIdString = userInfo["keyId"] as? String,
              let keyId = UUID(uuidString: keyIdString),
              let urgid = userInfo["urgid"] as? String else {
            completionHandler()
            return
        }

        // Verified push: the code the user typed into the notification's text field.
        let enteredCode = (response as? UNTextInputNotificationResponse)?.userText

        Task { @MainActor in
            do {
                if actionIdentifier == "APPROVE_ACTION" {
                    try await self.approvePush(keyId: keyId, urgid: urgid)
                } else if actionIdentifier == "VERIFY_ACTION" {
                    try await self.approvePush(keyId: keyId, urgid: urgid, stepUpCode: enteredCode)
                } else if actionIdentifier == "DENY_ACTION" {
                    try await self.denyPush(keyId: keyId, urgid: urgid)
                } else if actionIdentifier == UNNotificationDefaultActionIdentifier {
                    NSApp.activate(ignoringOtherApps: true)
                    if let delegate = NSApp.delegate {
                        _ = delegate.applicationShouldHandleReopen?(NSApp, hasVisibleWindows: false)
                    }
                }
            } catch {
                print("Error responding to notification action: \(error.localizedDescription)")

                // A rejected verification code leaves the transaction pending, so
                // bring the app forward and let the user retry in the main window.
                if actionIdentifier == "VERIFY_ACTION" {
                    NSApp.activate(ignoringOtherApps: true)
                    if let delegate = NSApp.delegate {
                        _ = delegate.applicationShouldHandleReopen?(NSApp, hasVisibleWindows: false)
                    }
                }
            }
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
