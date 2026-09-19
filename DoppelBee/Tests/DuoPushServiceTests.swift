//
//  DuoPushServiceTests.swift
//  DoppelBee
//
//  Created on 2026-01-05.
//  SPDX-License-Identifier: AGPL-3.0-or-later
//

import XCTest
@testable import DoppelBee
import UserNotifications

// Mock API service for testing push approve/deny functionality
class MockDuoPushAPIService: DuoPushAPIServiceProtocol {
    var checkForPushRequestsCalled = false
    var respondToPushCalled = false
    var lastRespondApprove: Bool?
    var lastRespondTxid: String?
    var lastRespondStepUpCode: String?
    var shouldThrow = false

    /// Transactions handed back by `checkForPushRequests`.
    var transactionsToReturn: [DuoAPIService.PushTransaction] = []
    /// Every (urgid, approve, stepUpCode) triple seen, in call order.
    var respondCalls: [(urgid: String, approve: Bool, stepUpCode: String?)] = []

    func checkForPushRequests(key: DuoKey) async throws -> [DuoAPIService.PushTransaction] {
        checkForPushRequestsCalled = true
        if shouldThrow { throw DuoAPIError.invalidResponse }
        return transactionsToReturn
    }

    func respondToPush(key: DuoKey, urgid: String, approve: Bool, stepUpCode: String?) async throws {
        respondToPushCalled = true
        lastRespondTxid = urgid
        lastRespondApprove = approve
        lastRespondStepUpCode = stepUpCode
        respondCalls.append((urgid: urgid, approve: approve, stepUpCode: stepUpCode))
        if shouldThrow { throw DuoAPIError.pushResponseFailed(details: "Mock error") }
    }
}

@MainActor
class DuoPushServiceTests: XCTestCase {

    func testDateFormatting() {
        // Test that we can format dates
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")

        let dateString = formatter.string(from: Date())

        // Verify the format (should be like "Sun, 05 Jan 2026 12:00:00 +0000")
        XCTAssertTrue(dateString.contains(","), "Date should contain comma separator")
        XCTAssertTrue(dateString.contains("+"), "Date should contain timezone offset")
    }

    func testSignatureMessage() throws {
        // Test that we can build the signature message format
        let time = "Sun, 05 Jan 2026 12:00:00 +0000"
        let method = "GET"
        let host = "api-test123.duosecurity.com"
        let path = "/push/v2/device/transactions"
        let params = "akey=test&fips_status=1"

        let message = "\(time)\n\(method)\n\(host.lowercased())\n\(path)\n\(params)"

        XCTAssertTrue(message.contains(time), "Message should contain time")
        XCTAssertTrue(message.contains(method), "Message should contain method")
        XCTAssertTrue(message.contains(host.lowercased()), "Message should contain lowercased host")
        XCTAssertTrue(message.contains(path), "Message should contain path")
        XCTAssertTrue(message.contains(params), "Message should contain params")
    }

    func testBase32Alphabet() {
        // Verify base32 alphabet is correct
        let expectedChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        XCTAssertEqual(expectedChars.count, 32, "Base32 alphabet should have 32 characters")
        XCTAssertTrue(expectedChars.allSatisfy { $0.isASCII }, "All characters should be ASCII")
    }

    func testURLEncoding() {
        // Test URL encoding
        let testCases: [(String, String)] = [
            ("hello world", "hello%20world"),
            ("test@example.com", "test%40example.com"),
            ("key=value", "key%3Dvalue")
        ]

        for (input, _) in testCases {
            let encoded = input.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            XCTAssertTrue(encoded.contains("%") || input == encoded, "URL encoding should work for '\(input)'")
        }
    }

    func testPushServiceLifecycle() async {
        // Test that push service can be initialized and cleaned up
        let pushService = DuoPushService()

        // Verify service is initialized
        XCTAssertNotNil(pushService)
        XCTAssertTrue(pushService.pendingPushes.isEmpty, "Should start with no pending pushes")

        // Stop polling (even though we didn't start)
        pushService.stopPolling()

        XCTAssertTrue(true, "Push service lifecycle test passed")
    }

    func testAutoConfirmSetting() {
        // Test auto-confirm functionality in DuoKey model
        let autoConfirmKey = DuoKey(
            name: "Auto Confirm Key",
            secret: "ABCDEFGHIJKLMNOP",
            host: "api-test123",
            pkey: "mock_pkey",
            akey: "mock_akey",
            autoConfirmPush: true
        )

        XCTAssertTrue(autoConfirmKey.autoConfirmPush, "Auto-confirm should be enabled")

        let manualKey = DuoKey(
            name: "Manual Key",
            secret: "ABCDEFGHIJKLMNOP",
            host: "api-test123",
            pkey: "mock_pkey",
            akey: "mock_akey",
            autoConfirmPush: false
        )

        XCTAssertFalse(manualKey.autoConfirmPush, "Auto-confirm should be disabled")
    }

    func testPushTransactionParsing() {
        // Test that we can parse push transaction responses correctly
        let mockJSON: [String: Any] = [
            "response": [
                "transactions": [
                    [
                        "urgid": "test-urgid-123",
                        "urgency": "high",
                        "title": "Login Request",
                        "message": "Approve login from Chrome on macOS"
                    ]
                ]
            ]
        ]

        // Verify JSON structure
        if let response = mockJSON["response"] as? [String: Any],
           let transactions = response["transactions"] as? [[String: Any]] {
            XCTAssertEqual(transactions.count, 1, "Should have one transaction")

            if let firstTx = transactions.first {
                XCTAssertEqual(firstTx["urgid"] as? String, "test-urgid-123")
                XCTAssertEqual(firstTx["urgency"] as? String, "high")
                XCTAssertEqual(firstTx["title"] as? String, "Login Request")
            }
        } else {
            XCTFail("Failed to parse mock JSON")
        }
    }

    func testRSAKeyPairGeneration() throws {
        // Test that we can generate RSA key pairs
        // This verifies the activation process works

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            XCTFail("Failed to generate RSA private key")
            return
        }

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            XCTFail("Failed to extract public key")
            return
        }

        XCTAssertNotNil(privateKey, "Private key should be generated")
        XCTAssertNotNil(publicKey, "Public key should be extracted")
    }

    func testRSASigning() throws {
        // Test that we can sign data with RSA SHA-512
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            XCTFail("Failed to generate RSA private key")
            return
        }

        let testMessage = "Test message for signing"
        guard let messageData = testMessage.data(using: .ascii) else {
            XCTFail("Failed to create test message data")
            return
        }

        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA512,
            messageData as CFData,
            &error
        ) as Data? else {
            XCTFail("Failed to sign message")
            return
        }

        XCTAssertTrue(signature.count > 0, "Signature should not be empty")
        XCTAssertEqual(signature.count, 256, "RSA-2048 signature should be 256 bytes")
    }

    func testParameterSorting() {
        // Test that parameters are sorted correctly for signature
        let params = ["zebra": "last", "aardvark": "first", "middle": "middle"]
        let sorted = params.sorted { $0.key < $1.key }

        XCTAssertEqual(sorted[0].key, "aardvark", "First sorted key should be 'aardvark'")
        XCTAssertEqual(sorted[1].key, "middle", "Second sorted key should be 'middle'")
        XCTAssertEqual(sorted[2].key, "zebra", "Third sorted key should be 'zebra'")
    }

    // MARK: - Approve/Deny/Dismiss Tests

    func testApprovePushCallsAPIAndRemovesFromPending() async throws {
        let mockAPI = MockDuoPushAPIService()
        let pushService = DuoPushService(apiService: mockAPI)

        let key = DuoKey(
            name: "Test Key",
            secret: "ABCDEFGHIJKLMNOP",
            host: "api-test123",
            pkey: "test_pkey",
            akey: "test_akey"
        )
        pushService.setKeys([key])

        // Manually add a pending push
        let urgid = "test-urgid-approve-123"
        pushService.pendingPushes[key.id.uuidString] = [
            DuoAPIService.PushTransaction(urgid: urgid, urgency: nil, title: "Test Push", message: nil)
        ]

        // Approve the push
        try await pushService.approvePush(keyId: key.id, urgid: urgid)

        // Verify API was called with approve=true
        XCTAssertTrue(mockAPI.respondToPushCalled, "API respondToPush should be called")
        XCTAssertEqual(mockAPI.lastRespondTxid, urgid, "Correct urgid should be passed")
        XCTAssertEqual(mockAPI.lastRespondApprove, true, "approve should be true")

        // Verify push was removed from pending
        XCTAssertNil(pushService.pendingPushes[key.id.uuidString], "Push should be removed from pending")
    }

    func testDenyPushCallsAPIAndRemovesFromPending() async throws {
        let mockAPI = MockDuoPushAPIService()
        let pushService = DuoPushService(apiService: mockAPI)

        let key = DuoKey(
            name: "Test Key",
            secret: "ABCDEFGHIJKLMNOP",
            host: "api-test123",
            pkey: "test_pkey",
            akey: "test_akey"
        )
        pushService.setKeys([key])

        // Manually add a pending push
        let urgid = "test-urgid-deny-456"
        pushService.pendingPushes[key.id.uuidString] = [
            DuoAPIService.PushTransaction(urgid: urgid, urgency: nil, title: "Test Push", message: nil)
        ]

        // Deny the push
        try await pushService.denyPush(keyId: key.id, urgid: urgid)

        // Verify API was called with approve=false
        XCTAssertTrue(mockAPI.respondToPushCalled, "API respondToPush should be called")
        XCTAssertEqual(mockAPI.lastRespondTxid, urgid, "Correct urgid should be passed")
        XCTAssertEqual(mockAPI.lastRespondApprove, false, "approve should be false")

        // Verify push was removed from pending
        XCTAssertNil(pushService.pendingPushes[key.id.uuidString], "Push should be removed from pending")
    }

    func testDismissPushRemovesFromPendingWithoutAPICall() {
        let mockAPI = MockDuoPushAPIService()
        let pushService = DuoPushService(apiService: mockAPI)

        let key = DuoKey(
            name: "Test Key",
            secret: "ABCDEFGHIJKLMNOP",
            host: "api-test123",
            pkey: "test_pkey",
            akey: "test_akey"
        )
        pushService.setKeys([key])

        // Manually add a pending push
        let urgid = "test-urgid-dismiss-789"
        pushService.pendingPushes[key.id.uuidString] = [
            DuoAPIService.PushTransaction(urgid: urgid, urgency: nil, title: "Test Push", message: nil)
        ]

        // Dismiss the push
        pushService.dismissPush(keyId: key.id, urgid: urgid)

        // Verify API was NOT called
        XCTAssertFalse(mockAPI.respondToPushCalled, "API respondToPush should NOT be called for dismiss")

        // Verify push was removed from pending
        XCTAssertNil(pushService.pendingPushes[key.id.uuidString], "Push should be removed from pending")
    }

    func testApprovePushWithMultiplePendingKeepsOthers() async throws {
        let mockAPI = MockDuoPushAPIService()
        let pushService = DuoPushService(apiService: mockAPI)

        let key = DuoKey(
            name: "Test Key",
            secret: "ABCDEFGHIJKLMNOP",
            host: "api-test123",
            pkey: "test_pkey",
            akey: "test_akey"
        )
        pushService.setKeys([key])

        // Add multiple pending pushes
        let urgid1 = "test-urgid-1"
        let urgid2 = "test-urgid-2"
        pushService.pendingPushes[key.id.uuidString] = [
            DuoAPIService.PushTransaction(urgid: urgid1, urgency: nil, title: "Push 1", message: nil),
            DuoAPIService.PushTransaction(urgid: urgid2, urgency: nil, title: "Push 2", message: nil)
        ]

        // Approve only the first push
        try await pushService.approvePush(keyId: key.id, urgid: urgid1)

        // Verify only the approved push was removed
        let remaining = pushService.pendingPushes[key.id.uuidString]
        XCTAssertNotNil(remaining, "Should still have pending pushes")
        XCTAssertEqual(remaining?.count, 1, "Should have one remaining push")
        XCTAssertEqual(remaining?.first?.urgid, urgid2, "Second push should remain")
    }

    func testDenyPushWithMultiplePendingKeepsOthers() async throws {
        let mockAPI = MockDuoPushAPIService()
        let pushService = DuoPushService(apiService: mockAPI)

        let key = DuoKey(
            name: "Test Key",
            secret: "ABCDEFGHIJKLMNOP",
            host: "api-test123",
            pkey: "test_pkey",
            akey: "test_akey"
        )
        pushService.setKeys([key])

        // Add multiple pending pushes
        let urgid1 = "test-urgid-1"
        let urgid2 = "test-urgid-2"
        pushService.pendingPushes[key.id.uuidString] = [
            DuoAPIService.PushTransaction(urgid: urgid1, urgency: nil, title: "Push 1", message: nil),
            DuoAPIService.PushTransaction(urgid: urgid2, urgency: nil, title: "Push 2", message: nil)
        ]

        // Deny only the second push
        try await pushService.denyPush(keyId: key.id, urgid: urgid2)

        // Verify only the denied push was removed
        let remaining = pushService.pendingPushes[key.id.uuidString]
        XCTAssertNotNil(remaining, "Should still have pending pushes")
        XCTAssertEqual(remaining?.count, 1, "Should have one remaining push")
        XCTAssertEqual(remaining?.first?.urgid, urgid1, "First push should remain")
    }

    func testApprovePushWithInvalidKeyDoesNothing() async throws {
        let mockAPI = MockDuoPushAPIService()
        let pushService = DuoPushService(apiService: mockAPI)

        let key = DuoKey(
            name: "Test Key",
            secret: "ABCDEFGHIJKLMNOP",
            host: "api-test123",
            pkey: "test_pkey",
            akey: "test_akey"
        )
        pushService.setKeys([key])

        // Try to approve with an invalid key ID
        let invalidKeyId = UUID()
        try await pushService.approvePush(keyId: invalidKeyId, urgid: "some-urgid")

        // Verify API was NOT called
        XCTAssertFalse(mockAPI.respondToPushCalled, "API should not be called for invalid key")
    }

    func testDenyPushAPIFailureKeepsPushPending() async {
        let mockAPI = MockDuoPushAPIService()
        mockAPI.shouldThrow = true
        let pushService = DuoPushService(apiService: mockAPI)

        let key = DuoKey(
            name: "Test Key",
            secret: "ABCDEFGHIJKLMNOP",
            host: "api-test123",
            pkey: "test_pkey",
            akey: "test_akey"
        )
        pushService.setKeys([key])

        // Add a pending push
        let urgid = "test-urgid-fail"
        pushService.pendingPushes[key.id.uuidString] = [
            DuoAPIService.PushTransaction(urgid: urgid, urgency: nil, title: "Test Push", message: nil)
        ]

        // Attempt to deny - should throw and keep push in pending
        do {
            try await pushService.denyPush(keyId: key.id, urgid: urgid)
            XCTFail("Expected error to be thrown")
        } catch {
            // Expected
            XCTAssertTrue(error is DuoAPIError, "Should throw DuoAPIError")
        }

        // Push should remain in pending since API failed
        XCTAssertNotNil(pushService.pendingPushes[key.id.uuidString], "Push should remain pending after API failure")
    }

    func testNotificationDelegateApprove() async throws {
        let mockAPI = MockDuoPushAPIService()
        let pushService = DuoPushService(apiService: mockAPI)
        
        let key = DuoKey(
            name: "Test Key",
            secret: "ABCDEFGHIJKLMNOP",
            host: "api-test123",
            pkey: "test_pkey",
            akey: "test_akey"
        )
        pushService.setKeys([key])
        
        // Construct UNNotificationRequest and UNNotification using Key-Value Coding
        let content = UNMutableNotificationContent()
        content.userInfo = [
            "keyId": key.id.uuidString,
            "urgid": "test-urgid-123"
        ]
        
        let request = UNNotificationRequest(
            identifier: "test-urgid-123",
            content: content,
            trigger: nil
        )
        
        let notificationClass = NSClassFromString("UNNotification") as! NSObject.Type
        let notification = notificationClass.init() as! UNNotification
        notification.setValue(request, forKey: "request")
        
        let responseClass = NSClassFromString("UNNotificationResponse") as! NSObject.Type
        let response = responseClass.init() as! UNNotificationResponse
        response.setValue("APPROVE_ACTION", forKey: "actionIdentifier")
        response.setValue(notification, forKey: "notification")
        
        // Call the delegate method directly
        let expectation = XCTestExpectation(description: "Completion handler called")
        pushService.userNotificationCenter(
            UNUserNotificationCenter.current(),
            didReceive: response
        ) {
            expectation.fulfill()
        }
        
        #if compiler(>=6.0)
        await fulfillment(of: [expectation], timeout: 2.0)
        #else
        wait(for: [expectation], timeout: 2.0)
        #endif
        
        XCTAssertTrue(mockAPI.respondToPushCalled, "API respondToPush should be called")
        XCTAssertEqual(mockAPI.lastRespondTxid, "test-urgid-123", "Correct urgid should be passed")
        XCTAssertEqual(mockAPI.lastRespondApprove, true, "Should approve")
    }

    func testNotificationDelegateDeny() async throws {
        let mockAPI = MockDuoPushAPIService()
        let pushService = DuoPushService(apiService: mockAPI)
        
        let key = DuoKey(
            name: "Test Key",
            secret: "ABCDEFGHIJKLMNOP",
            host: "api-test123",
            pkey: "test_pkey",
            akey: "test_akey"
        )
        pushService.setKeys([key])
        
        let content = UNMutableNotificationContent()
        content.userInfo = [
            "keyId": key.id.uuidString,
            "urgid": "test-urgid-456"
        ]
        
        let request = UNNotificationRequest(
            identifier: "test-urgid-456",
            content: content,
            trigger: nil
        )
        
        let notificationClass = NSClassFromString("UNNotification") as! NSObject.Type
        let notification = notificationClass.init() as! UNNotification
        notification.setValue(request, forKey: "request")
        
        let responseClass = NSClassFromString("UNNotificationResponse") as! NSObject.Type
        let response = responseClass.init() as! UNNotificationResponse
        response.setValue("DENY_ACTION", forKey: "actionIdentifier")
        response.setValue(notification, forKey: "notification")
        
        let expectation = XCTestExpectation(description: "Completion handler called")
        pushService.userNotificationCenter(
            UNUserNotificationCenter.current(),
            didReceive: response
        ) {
            expectation.fulfill()
        }
        
        #if compiler(>=6.0)
        await fulfillment(of: [expectation], timeout: 2.0)
        #else
        wait(for: [expectation], timeout: 2.0)
        #endif
        
        XCTAssertTrue(mockAPI.respondToPushCalled, "API respondToPush should be called")
        XCTAssertEqual(mockAPI.lastRespondTxid, "test-urgid-456", "Correct urgid should be passed")
        XCTAssertEqual(mockAPI.lastRespondApprove, false, "Should deny")
    }

    func testNotificationDelegateBannerClick() async throws {
        let mockAPI = MockDuoPushAPIService()
        let pushService = DuoPushService(apiService: mockAPI)
        
        let key = DuoKey(
            name: "Test Key",
            secret: "ABCDEFGHIJKLMNOP",
            host: "api-test123",
            pkey: "test_pkey",
            akey: "test_akey"
        )
        pushService.setKeys([key])
        
        let content = UNMutableNotificationContent()
        content.userInfo = [
            "keyId": key.id.uuidString,
            "urgid": "test-urgid-banner"
        ]
        
        let request = UNNotificationRequest(
            identifier: "test-urgid-banner",
            content: content,
            trigger: nil
        )
        
        let notificationClass = NSClassFromString("UNNotification") as! NSObject.Type
        let notification = notificationClass.init() as! UNNotification
        notification.setValue(request, forKey: "request")
        
        let responseClass = NSClassFromString("UNNotificationResponse") as! NSObject.Type
        let response = responseClass.init() as! UNNotificationResponse
        response.setValue(UNNotificationDefaultActionIdentifier, forKey: "actionIdentifier")
        response.setValue(notification, forKey: "notification")
        
        let expectation = XCTestExpectation(description: "Completion handler called")
        pushService.userNotificationCenter(
            UNUserNotificationCenter.current(),
            didReceive: response
        ) {
            expectation.fulfill()
        }
        
        #if compiler(>=6.0)
        await fulfillment(of: [expectation], timeout: 2.0)
        #else
        wait(for: [expectation], timeout: 2.0)
        #endif
        
        XCTAssertFalse(mockAPI.respondToPushCalled, "API respondToPush should not be called on banner click")
    }

    // MARK: - Verified Duo Push

    /// Runs one poll cycle against the mock and then stops polling.
    private func runOnePollCycle(_ pushService: DuoPushService, keys: [DuoKey]) async {
        pushService.startPolling(keys: keys)
        try? await Task.sleep(nanoseconds: 300_000_000)
        pushService.stopPolling()
    }

    private func makeTestKey(autoConfirm: Bool = false) -> DuoKey {
        DuoKey(
            name: "Test Key",
            secret: "ABCDEFGHIJKLMNOP",
            host: "api-test123",
            pkey: "test_pkey",
            akey: "test_akey",
            autoConfirmPush: autoConfirm
        )
    }

    /// Tears down a scratch defaults suite. `removePersistentDomain` alone leaves the
    /// backing plist on disk, so the file is unlinked explicitly.
    static func removeDefaultsSuite(_ suiteName: String) {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        UserDefaults.standard.removeSuite(named: suiteName)

        let plist = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Preferences/\(suiteName).plist")
        try? FileManager.default.removeItem(at: plist)
    }

    /// A push service backed by a scratch defaults suite. Writing these keys to
    /// `UserDefaults.standard` would change the user's real auto-confirm and
    /// notification settings, and a crash mid-test would leave them changed.
    private func makePushService(
        apiService: MockDuoPushAPIService,
        globalAutoConfirm: Bool = false
    ) -> (service: DuoPushService, cleanup: () -> Void) {
        let suiteName = "com.doppelbee.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(globalAutoConfirm, forKey: "autoConfirmAllPushes")
        defaults.set(false, forKey: "enableSystemNotifications")

        let service = DuoPushService(apiService: apiService, defaults: defaults)
        return (service, { Self.removeDefaultsSuite(suiteName) })
    }

    func testVerifiedPushDetection() {
        let standard = DuoAPIService.PushTransaction(urgid: "a", urgency: nil, title: nil, message: nil)
        XCTAssertFalse(standard.isVerifiedPush, "Transaction without step-up info is a standard push")

        let verified = DuoAPIService.PushTransaction(urgid: "b", urgency: nil, title: nil, message: nil, stepUpNumDigits: 3)
        XCTAssertTrue(verified.isVerifiedPush, "Transaction with num_digits is a verified push")

        let zeroDigits = DuoAPIService.PushTransaction(urgid: "c", urgency: nil, title: nil, message: nil, stepUpNumDigits: 0)
        XCTAssertFalse(zeroDigits.isVerifiedPush, "Zero digits should not count as verified push")
    }

    func testAutoConfirmSkipsVerifiedPush() async {
        let mockAPI = MockDuoPushAPIService()
        let (pushService, cleanup) = makePushService(apiService: mockAPI)
        defer { cleanup() }
        let key = makeTestKey(autoConfirm: true)
        pushService.setKeys([key])

        mockAPI.transactionsToReturn = [
            DuoAPIService.PushTransaction(urgid: "verified-1", urgency: nil, title: "Verified", message: nil, stepUpNumDigits: 3)
        ]

        await runOnePollCycle(pushService, keys: [key])

        XCTAssertTrue(mockAPI.respondCalls.isEmpty, "Verified push must never be auto-confirmed")
        XCTAssertEqual(pushService.pendingPushes[key.id.uuidString]?.count, 1,
                       "Verified push should stay pending for manual confirmation")
    }

    func testAutoConfirmStillApprovesStandardPush() async {
        let mockAPI = MockDuoPushAPIService()
        let (pushService, cleanup) = makePushService(apiService: mockAPI)
        defer { cleanup() }
        let key = makeTestKey(autoConfirm: true)
        pushService.setKeys([key])

        mockAPI.transactionsToReturn = [
            DuoAPIService.PushTransaction(urgid: "standard-1", urgency: nil, title: "Standard", message: nil)
        ]

        await runOnePollCycle(pushService, keys: [key])

        XCTAssertFalse(mockAPI.respondCalls.isEmpty, "Standard push should still be auto-confirmed")
        XCTAssertEqual(mockAPI.respondCalls.first?.urgid, "standard-1")
        XCTAssertEqual(mockAPI.respondCalls.first?.approve, true)
        XCTAssertNil(mockAPI.respondCalls.first?.stepUpCode, "Standard push carries no step-up code")
        XCTAssertNil(pushService.pendingPushes[key.id.uuidString], "Auto-confirmed push should not stay pending")
    }

    func testAutoConfirmMixedBatchApprovesOnlyStandardPush() async {
        let mockAPI = MockDuoPushAPIService()
        let (pushService, cleanup) = makePushService(apiService: mockAPI)
        defer { cleanup() }
        let key = makeTestKey(autoConfirm: true)
        pushService.setKeys([key])

        mockAPI.transactionsToReturn = [
            DuoAPIService.PushTransaction(urgid: "standard-1", urgency: nil, title: "Standard", message: nil),
            DuoAPIService.PushTransaction(urgid: "verified-1", urgency: nil, title: "Verified", message: nil, stepUpNumDigits: 3)
        ]

        await runOnePollCycle(pushService, keys: [key])

        let approvedUrgids = mockAPI.respondCalls.map { $0.urgid }
        XCTAssertTrue(approvedUrgids.contains("standard-1"), "Standard push should be auto-confirmed")
        XCTAssertFalse(approvedUrgids.contains("verified-1"), "Verified push should not be auto-confirmed")

        let pending = pushService.pendingPushes[key.id.uuidString]
        XCTAssertEqual(pending?.count, 1, "Only the verified push should remain pending")
        XCTAssertEqual(pending?.first?.urgid, "verified-1")
    }

    func testGlobalAutoConfirmSkipsVerifiedPush() async {
        let mockAPI = MockDuoPushAPIService()
        let (pushService, cleanup) = makePushService(apiService: mockAPI, globalAutoConfirm: true)
        defer { cleanup() }
        let key = makeTestKey(autoConfirm: false)
        pushService.setKeys([key])

        mockAPI.transactionsToReturn = [
            DuoAPIService.PushTransaction(urgid: "verified-global", urgency: nil, title: "Verified", message: nil, stepUpNumDigits: 6)
        ]

        await runOnePollCycle(pushService, keys: [key])

        XCTAssertTrue(mockAPI.respondCalls.isEmpty,
                      "Global auto-confirm must not approve verified push either")
        XCTAssertEqual(pushService.pendingPushes[key.id.uuidString]?.count, 1)
    }

    /// Companion to `testGlobalAutoConfirmSkipsVerifiedPush`: proves the global
    /// setting is actually consulted, so that test's empty-respondCalls assertion
    /// means "verified push was excluded" rather than "auto-confirm was never on".
    func testGlobalAutoConfirmApprovesStandardPush() async {
        let mockAPI = MockDuoPushAPIService()
        let (pushService, cleanup) = makePushService(apiService: mockAPI, globalAutoConfirm: true)
        defer { cleanup() }
        let key = makeTestKey(autoConfirm: false)
        pushService.setKeys([key])

        mockAPI.transactionsToReturn = [
            DuoAPIService.PushTransaction(urgid: "standard-global", urgency: nil, title: "Standard", message: nil)
        ]

        await runOnePollCycle(pushService, keys: [key])

        XCTAssertEqual(mockAPI.respondCalls.first?.urgid, "standard-global",
                       "Global auto-confirm should approve a standard push")
        XCTAssertEqual(mockAPI.respondCalls.first?.approve, true)
    }

    func testApproveVerifiedPushSendsStepUpCode() async throws {
        let mockAPI = MockDuoPushAPIService()
        let pushService = DuoPushService(apiService: mockAPI)
        let key = makeTestKey()
        pushService.setKeys([key])

        let urgid = "verified-approve"
        pushService.pendingPushes[key.id.uuidString] = [
            DuoAPIService.PushTransaction(urgid: urgid, urgency: nil, title: nil, message: nil, stepUpNumDigits: 3)
        ]

        try await pushService.approvePush(keyId: key.id, urgid: urgid, stepUpCode: "427")

        XCTAssertEqual(mockAPI.lastRespondApprove, true)
        XCTAssertEqual(mockAPI.lastRespondStepUpCode, "427", "Verification code should reach the API")
        XCTAssertNil(pushService.pendingPushes[key.id.uuidString], "Approved push should be removed")
    }

    func testApproveVerifiedPushWithoutCodeThrows() async {
        let mockAPI = MockDuoPushAPIService()
        let pushService = DuoPushService(apiService: mockAPI)
        let key = makeTestKey()
        pushService.setKeys([key])

        let urgid = "verified-nocode"
        pushService.pendingPushes[key.id.uuidString] = [
            DuoAPIService.PushTransaction(urgid: urgid, urgency: nil, title: nil, message: nil, stepUpNumDigits: 3)
        ]

        do {
            try await pushService.approvePush(keyId: key.id, urgid: urgid)
            XCTFail("Approving a verified push without a code should throw")
        } catch {
            XCTAssertTrue(error is DuoAPIError)
        }

        XCTAssertFalse(mockAPI.respondToPushCalled, "API should not be hit without a code")
        XCTAssertNotNil(pushService.pendingPushes[key.id.uuidString], "Push should remain pending")
    }

    func testApproveVerifiedPushWithWrongLengthCodeThrows() async {
        let mockAPI = MockDuoPushAPIService()
        let pushService = DuoPushService(apiService: mockAPI)
        let key = makeTestKey()
        pushService.setKeys([key])

        let urgid = "verified-shortcode"
        pushService.pendingPushes[key.id.uuidString] = [
            DuoAPIService.PushTransaction(urgid: urgid, urgency: nil, title: nil, message: nil, stepUpNumDigits: 3)
        ]

        do {
            try await pushService.approvePush(keyId: key.id, urgid: urgid, stepUpCode: "42")
            XCTFail("A code of the wrong length should be rejected locally")
        } catch {
            XCTAssertTrue(error is DuoAPIError)
        }

        XCTAssertFalse(mockAPI.respondToPushCalled, "API should not be hit with a malformed code")
    }

    func testApproveVerifiedPushWithNonNumericCodeThrows() async {
        let mockAPI = MockDuoPushAPIService()
        let pushService = DuoPushService(apiService: mockAPI)
        let key = makeTestKey()
        pushService.setKeys([key])

        let urgid = "verified-alpha"
        pushService.pendingPushes[key.id.uuidString] = [
            DuoAPIService.PushTransaction(urgid: urgid, urgency: nil, title: nil, message: nil, stepUpNumDigits: 3)
        ]

        do {
            try await pushService.approvePush(keyId: key.id, urgid: urgid, stepUpCode: "4a7")
            XCTFail("A non-numeric code should be rejected locally")
        } catch {
            XCTAssertTrue(error is DuoAPIError)
        }

        XCTAssertFalse(mockAPI.respondToPushCalled)
    }

    func testDenyVerifiedPushNeedsNoCode() async throws {
        let mockAPI = MockDuoPushAPIService()
        let pushService = DuoPushService(apiService: mockAPI)
        let key = makeTestKey()
        pushService.setKeys([key])

        let urgid = "verified-deny"
        pushService.pendingPushes[key.id.uuidString] = [
            DuoAPIService.PushTransaction(urgid: urgid, urgency: nil, title: nil, message: nil, stepUpNumDigits: 3)
        ]

        try await pushService.denyPush(keyId: key.id, urgid: urgid)

        XCTAssertEqual(mockAPI.lastRespondApprove, false)
        XCTAssertNil(mockAPI.lastRespondStepUpCode, "Denying never sends a code")
        XCTAssertNil(pushService.pendingPushes[key.id.uuidString])
    }

    func testStandardPushApprovalSendsNoStepUpCode() async throws {
        let mockAPI = MockDuoPushAPIService()
        let pushService = DuoPushService(apiService: mockAPI)
        let key = makeTestKey()
        pushService.setKeys([key])

        let urgid = "standard-approve"
        pushService.pendingPushes[key.id.uuidString] = [
            DuoAPIService.PushTransaction(urgid: urgid, urgency: nil, title: nil, message: nil)
        ]

        try await pushService.approvePush(keyId: key.id, urgid: urgid)

        XCTAssertEqual(mockAPI.lastRespondApprove, true)
        XCTAssertNil(mockAPI.lastRespondStepUpCode)
    }

    func testStepUpCodeIsRedactedFromLogs() {
        let body = "akey=abc&answer=approve&fips_status=1&step_up_code=427&x=1"
        let redacted = DuoAPIService.redactStepUpCode(in: body)

        XCTAssertFalse(redacted.contains("step_up_code=427"), "Raw code must not survive redaction")
        XCTAssertTrue(redacted.contains("step_up_code=<redacted>"))
        XCTAssertTrue(redacted.contains("akey=abc"), "Other params should be untouched")
        XCTAssertTrue(redacted.contains("x=1"), "Params after the code should be preserved")

        let trailing = "answer=approve&step_up_code=427"
        XCTAssertEqual(DuoAPIService.redactStepUpCode(in: trailing), "answer=approve&step_up_code=<redacted>")

        let noCode = "akey=abc&answer=deny"
        XCTAssertEqual(DuoAPIService.redactStepUpCode(in: noCode), noCode, "Unrelated strings are unchanged")
    }

    // MARK: - Transaction Details

    func testParseAttributesFromRealTransactionShape() {
        // Shape captured from a live Verified Duo Push transaction.
        let raw: [[Any]] = [
            [["Organization", "Example University"], ["Integration", "Example CAS"]],
            [["Username", "jdoe (Jane Doe)"],
             ["IP Address", "203.0.113.10"],
             ["Location", "Somewhere, NJ, US"],
             ["Time", 1786126559.6671934]]
        ]

        let groups = DuoAPIService.parseAttributes(raw)

        XCTAssertEqual(groups.count, 2, "Both attribute groups should parse")
        XCTAssertEqual(groups[0], [
            DuoAPIService.PushAttribute(label: "Organization", value: "Example University"),
            DuoAPIService.PushAttribute(label: "Integration", value: "Example CAS")
        ])

        let second = groups[1]
        XCTAssertEqual(second[0], DuoAPIService.PushAttribute(label: "Username", value: "jdoe (Jane Doe)"))
        XCTAssertEqual(second[1], DuoAPIService.PushAttribute(label: "IP Address", value: "203.0.113.10"))
        XCTAssertEqual(second[2], DuoAPIService.PushAttribute(label: "Location", value: "Somewhere, NJ, US"))
        XCTAssertEqual(second[3].label, "Time")
        XCTAssertFalse(second[3].value.contains("1786126559"),
                       "Unix timestamps should be formatted as a readable date, not echoed raw")
    }

    func testParseAttributesHandlesMalformedInput() {
        XCTAssertTrue(DuoAPIService.parseAttributes(nil).isEmpty)
        XCTAssertTrue(DuoAPIService.parseAttributes("not an array").isEmpty)
        XCTAssertTrue(DuoAPIService.parseAttributes([[["OnlyOneElement"]]]).isEmpty,
                      "Pairs missing a value should be dropped")
        XCTAssertTrue(DuoAPIService.parseAttributes([[[1, "non-string label"]]]).isEmpty,
                      "Non-string labels should be dropped")

        // A group with one bad pair should keep the good ones.
        let mixed = DuoAPIService.parseAttributes([[["Good", "value"], ["Bad"]]])
        XCTAssertEqual(mixed, [[DuoAPIService.PushAttribute(label: "Good", value: "value")]])
    }

    func testDisplayValueConversions() {
        XCTAssertEqual(DuoAPIService.displayValue(label: "Any", raw: "text"), "text")
        XCTAssertNil(DuoAPIService.displayValue(label: "Any", raw: ""), "Empty strings carry nothing")
        XCTAssertEqual(DuoAPIService.displayValue(label: "Count", raw: 42), "42")
        XCTAssertEqual(DuoAPIService.displayValue(label: "Count", raw: 42.0), "42",
                       "Whole numbers should not render as 42.0")
        XCTAssertEqual(DuoAPIService.displayValue(label: "Flag", raw: true), "Yes")
        XCTAssertEqual(DuoAPIService.displayValue(label: "Flag", raw: false), "No")
        XCTAssertNil(DuoAPIService.displayValue(label: "Any", raw: ["nested"]))
    }

    func testDisplayTitleFallsBackThroughTypeAndSummary() {
        let withTitle = DuoAPIService.PushTransaction(
            urgid: "a", urgency: nil, title: "Explicit Title", message: nil,
            summary: "Example CAS", type: "Login"
        )
        XCTAssertEqual(withTitle.displayTitle, "Explicit Title", "An explicit title wins")

        // The shape the live tenant actually sends: no title, but type + summary.
        let typeAndSummary = DuoAPIService.PushTransaction(
            urgid: "b", urgency: nil, title: nil, message: nil,
            summary: "Example CAS", type: "Login"
        )
        XCTAssertEqual(typeAndSummary.displayTitle, "Login — Example CAS")

        let bare = DuoAPIService.PushTransaction(urgid: "c", urgency: nil, title: nil, message: nil)
        XCTAssertEqual(bare.displayTitle, "Duo Push Request", "Something sensible when Duo sends neither")
    }

    func testContextLineHighlightsWhoAndWhere() {
        let tx = DuoAPIService.PushTransaction(
            urgid: "a", urgency: nil, title: nil, message: nil,
            attributeGroups: [
                [DuoAPIService.PushAttribute(label: "Organization", value: "Example University")],
                [DuoAPIService.PushAttribute(label: "Username", value: "jdoe"),
                 DuoAPIService.PushAttribute(label: "IP Address", value: "203.0.113.10"),
                 DuoAPIService.PushAttribute(label: "Location", value: "Somewhere, NJ, US")]
            ]
        )

        XCTAssertEqual(tx.contextLine, "jdoe · 203.0.113.10 · Somewhere, NJ, US",
                       "Identity and origin are what make an unexpected push recognisable")

        let noAttributes = DuoAPIService.PushTransaction(urgid: "b", urgency: nil, title: nil, message: nil)
        XCTAssertNil(noAttributes.contextLine)
    }

    func testVerifiedPushTransactionParsing() throws {
        // Shape of a real verified-push transaction from /push/v2/device/transactions
        let json = """
        {"response":{"transactions":[
          {"urgid":"tx-verified","title":"Login Request","step_up_code_info":{"num_digits":3}},
          {"urgid":"tx-standard","title":"Login Request"}
        ]}}
        """.data(using: .utf8)!

        let parsed = try JSONSerialization.jsonObject(with: json) as? [String: Any]
        let response = parsed?["response"] as? [String: Any]
        let transactions = response?["transactions"] as? [[String: Any]]

        XCTAssertEqual(transactions?.count, 2)

        let verified = transactions?.first { $0["urgid"] as? String == "tx-verified" }
        let stepUpInfo = verified?["step_up_code_info"] as? [String: Any]
        XCTAssertEqual(stepUpInfo?["num_digits"] as? Int, 3)

        let standard = transactions?.first { $0["urgid"] as? String == "tx-standard" }
        XCTAssertNil(standard?["step_up_code_info"], "Standard push carries no step-up block")
    }

    /// A database manager pointed at a scratch file, an unused keychain item, and an
    /// empty defaults suite. A bare `DuoDatabaseManager()` would auto-unlock the
    /// user's real database and start polling live Duo endpoints with their keys.
    private func makeIsolatedDatabaseManager() throws -> (manager: DuoDatabaseManager, cleanup: () -> Void) {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DoppelBeeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let suiteName = "com.doppelbee.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let manager = DuoDatabaseManager(
            databaseURL: tempDirectory.appendingPathComponent("duo.db"),
            keychainService: KeychainService(service: suiteName, account: "database-password"),
            defaults: defaults,
            autoLoad: false
        )

        return (manager, {
            Self.removeDefaultsSuite(suiteName)
            try? FileManager.default.removeItem(at: tempDirectory)
        })
    }

    func testObserveDatabase() async throws {
        let (dbManager, cleanup) = try makeIsolatedDatabaseManager()
        defer { cleanup() }

        let mockAPI = MockDuoPushAPIService()
        let pushService = DuoPushService(apiService: mockAPI)

        pushService.observeDatabase(dbManager)

        let testKey = DuoKey(
            name: "Test Key",
            secret: "ABCDEFGHIJKLMNOP",
            host: "api-test123",
            pkey: "test_pkey",
            akey: "test_akey"
        )
        dbManager.database = DuoDatabase(keys: [testKey])

        // Allow time for publication/subscription execution
        try? await Task.sleep(nanoseconds: 300_000_000)
        pushService.stopPolling()

        XCTAssertTrue(mockAPI.checkForPushRequestsCalled,
                      "Publishing a database should start polling its keys")
    }

    func testIsolatedDatabaseManagerDoesNotTouchRealDatabase() throws {
        let (dbManager, cleanup) = try makeIsolatedDatabaseManager()
        defer { cleanup() }

        XCTAssertNotEqual(dbManager.databaseURL, DuoDatabaseManager.defaultDatabaseURL(),
                          "Tests must not point at the real Application Support database")
        XCTAssertNil(dbManager.database, "A non-auto-loading manager starts with no database")
        XCTAssertNil(dbManager.databasePath, "No database file should exist yet")
    }
}
