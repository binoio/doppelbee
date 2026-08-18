//
//  DuoAPIService.swift
//  DuoBee
//
//  Created on 2026-01-04.
//  SPDX-License-Identifier: MIT
//

import Foundation
import Security

class DuoAPIService {
    /// Verbose request logging prints akey, pkey, and signature material, which are
    /// long-lived credentials. Off unless deliberately enabled with
    /// `defaults write edu.princeton.orfe.duobee duoVerboseLogging -bool YES`.
    private static let verboseLoggingEnabled = UserDefaults.standard.bool(forKey: "duoVerboseLogging")

    private func verboseLog(_ message: @autoclosure () -> String) {
        guard Self.verboseLoggingEnabled else { return }
        NSLog("%@", message())
    }

    struct ActivationResult {
        let secret: String
        let host: String
        let name: String
        let publicKey: String
        let privateKey: String
        let pkey: String
        let akey: String
    }

    func parseActivationURL(_ urlString: String) -> (host: String, code: String)? {
        // Expected format: https://m-<activation-host>.duosecurity.com/activate/<activation-code>
        // Should be transformed to: api-<activation-host>
        guard let url = URL(string: urlString),
              let host = url.host,
              host.hasSuffix(".duosecurity.com") else {
            return nil
        }

        // Extract activation code from path
        let pathComponents = url.pathComponents
        guard pathComponents.count >= 3,
              pathComponents[1] == "activate" else {
            return nil
        }
        let code = pathComponents[2]

        // Transform m-<host> to api-<host>
        let hostParts = host.components(separatedBy: ".")
        guard hostParts.count >= 3,
              hostParts[0].hasPrefix("m-") else {
            return nil
        }

        let activationHost = String(hostParts[0].dropFirst(2)) // Remove "m-"
        let apiHost = "api-" + activationHost

        return (apiHost, code)
    }

    func activate(host: String, code: String) async throws -> ActivationResult {
        // Generate RSA key pair
        let (publicKeyPEM, privateKeyPEM) = try generateRSAKeyPair()

        // Construct activation URL
        let urlString = "https://\(host).duosecurity.com/push/v2/activation/\(code)"
        guard let url = URL(string: urlString) else {
            throw DuoAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // Set headers to mimic iOS Duo Mobile app
        request.setValue("DuoMobileApp/4.73.0.873.1 (arm64; iOS 18.1); Client: Foundation", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("en-us", forHTTPHeaderField: "Accept-Language")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")

        // Prepare POST data with device information
        let postData: [String: String] = [
            "app_id": "com.duosecurity.DuoMobile",
            "app_version": "4.73.0.873.1",
            "ble_status": "allowed",
            "build_version": "24B5055e",
            "customer_protocol": "1",
            "device_name": "iPad",
            "jailbroken": "false",
            "language": "en",
            "manufacturer": "Apple",
            "model": "arm64",
            "notification_status": "not_determined",
            "passcode_status": "true",
            "pkpush": "rsa-sha512",
            "platform": "iOS",
            "pubkey": publicKeyPEM,
            "region": "US",
            "security_patch_level": "",
            "touchid_status": "true",
            "version": "18.1"
        ]

        // Create form-encoded body
        let bodyString = postData.map { "\($0.key)=\(urlEncode($0.value))" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DuoAPIError.invalidResponse
        }

        // Debug logging
        if httpResponse.statusCode != 200 {
            let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
            print("Activation failed with status \(httpResponse.statusCode)")
            print("Response: \(responseString)")
            throw DuoAPIError.activationFailed
        }

        // Parse JSON response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseDict = json["response"] as? [String: Any],
              let secret = responseDict["hotp_secret"] as? String,
              let pkey = responseDict["pkey"] as? String,
              let akey = responseDict["akey"] as? String else {
            // The activation payload carries hotp_secret/pkey/akey, so the body is
            // only dumped when verbose logging is explicitly turned on.
            verboseLog("Invalid activation response format: \(String(data: data, encoding: .utf8) ?? "Unable to decode response")")
            throw DuoAPIError.invalidResponse
        }

        // Extract customer name if available
        let customerName = responseDict["customer_name"] as? String ?? "Duo Account"

        // Base32 encode the secret (matching Python implementation)
        guard let secretData = secret.data(using: .ascii) else {
            throw DuoAPIError.invalidResponse
        }
        let base32Secret = self.base32Encode(secretData)

        return ActivationResult(
            secret: base32Secret,
            host: host,
            name: customerName,
            publicKey: publicKeyPEM,
            privateKey: privateKeyPEM,
            pkey: pkey,
            akey: akey
        )
    }

    private func generateRSAKeyPair() throws -> (publicKey: String, privateKey: String) {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw DuoAPIError.keyGenerationFailed
        }

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw DuoAPIError.keyGenerationFailed
        }

        // Export keys to PEM format
        let publicKeyPEM = try exportKeyToPEM(publicKey, isPublic: true)
        let privateKeyPEM = try exportKeyToPEM(privateKey, isPublic: false)

        return (publicKeyPEM, privateKeyPEM)
    }

    private func exportKeyToPEM(_ key: SecKey, isPublic: Bool) throws -> String {
        var error: Unmanaged<CFError>?
        guard let keyData = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
            throw DuoAPIError.keyExportFailed
        }

        let base64Key = keyData.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        let header = isPublic ? "-----BEGIN PUBLIC KEY-----" : "-----BEGIN RSA PRIVATE KEY-----"
        let footer = isPublic ? "-----END PUBLIC KEY-----" : "-----END RSA PRIVATE KEY-----"

        return "\(header)\n\(base64Key)\n\(footer)"
    }

    private func urlEncode(_ string: String) -> String {
        var allowedCharacters = CharacterSet.alphanumerics
        allowedCharacters.insert(charactersIn: "-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? string
    }

    // MARK: - Duo Push Support

    /// One labelled detail from a transaction's `attributes` block, e.g.
    /// ("IP Address", "140.180.240.71").
    struct PushAttribute: Codable, Equatable, Hashable {
        let label: String
        let value: String
    }

    struct PushTransaction: Codable {
        let urgid: String
        let urgency: String?
        let title: String?
        let message: String?
        /// Number of digits shown on the access device that the user must enter to
        /// approve. Only present on Verified Duo Push transactions.
        let stepUpNumDigits: Int?
        /// Short description of the integration being logged into, e.g. "Princeton CAS".
        let summary: String?
        /// Transaction kind, e.g. "Login".
        let type: String?
        /// Grouped request details. Duo sends these instead of title/message on at
        /// least some tenants, and they carry the context (who, where, from what IP)
        /// that makes an approve/deny decision informed.
        let attributeGroups: [[PushAttribute]]

        init(
            urgid: String,
            urgency: String?,
            title: String?,
            message: String?,
            stepUpNumDigits: Int? = nil,
            summary: String? = nil,
            type: String? = nil,
            attributeGroups: [[PushAttribute]] = []
        ) {
            self.urgid = urgid
            self.urgency = urgency
            self.title = title
            self.message = message
            self.stepUpNumDigits = stepUpNumDigits
            self.summary = summary
            self.type = type
            self.attributeGroups = attributeGroups
        }

        var isVerifiedPush: Bool {
            (stepUpNumDigits ?? 0) > 0
        }

        var attributes: [PushAttribute] {
            attributeGroups.flatMap { $0 }
        }

        /// Heading for the request. Falls back through title, then type/summary, so
        /// tenants that send either shape get something meaningful.
        var displayTitle: String {
            if let title = title, !title.isEmpty { return title }

            let parts = [type, summary]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            if !parts.isEmpty { return parts.joined(separator: " — ") }

            return "Duo Push Request"
        }

        /// One-line context for notifications: who is logging in and from where.
        /// This is what lets someone spot a push they did not initiate.
        var contextLine: String? {
            let preferred = ["Username", "IP Address", "Location"]
            let highlights = preferred.compactMap { label in
                attributes.first(where: { $0.label == label })?.value
            }
            if !highlights.isEmpty { return highlights.joined(separator: " · ") }

            guard !attributes.isEmpty else { return nil }
            return attributes.map { $0.value }.joined(separator: " · ")
        }
    }

    /// Converts one `attributes` entry's value, which may be a string, number, or
    /// bool, into something displayable. Duo sends "Time" as a Unix timestamp.
    static func displayValue(label: String, raw: Any) -> String? {
        if let string = raw as? String {
            return string.isEmpty ? nil : string
        }

        guard let number = raw as? NSNumber else { return nil }

        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue ? "Yes" : "No"
        }

        if label.caseInsensitiveCompare("Time") == .orderedSame {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: Date(timeIntervalSince1970: number.doubleValue))
        }

        let value = number.doubleValue
        if value == value.rounded(), abs(value) < 1e15 {
            return String(number.int64Value)
        }
        return String(value)
    }

    /// Parses Duo's nested `attributes` shape: groups of [label, value] pairs.
    static func parseAttributes(_ raw: Any?) -> [[PushAttribute]] {
        guard let groups = raw as? [[Any]] else { return [] }

        return groups.compactMap { group -> [PushAttribute]? in
            let parsed = group.compactMap { entry -> PushAttribute? in
                guard let pair = entry as? [Any], pair.count >= 2,
                      let label = pair[0] as? String, !label.isEmpty,
                      let value = displayValue(label: label, raw: pair[1]) else { return nil }
                return PushAttribute(label: label, value: value)
            }
            return parsed.isEmpty ? nil : parsed
        }
    }

    func checkForPushRequests(key: DuoKey) async throws -> [PushTransaction] {
        guard let pkey = key.pkey, let akey = key.akey, let privateKeyPEM = key.privateKey else {
            throw DuoAPIError.missingPushCredentials
        }

        let path = "/push/v2/device/transactions"
        let host = "\(key.host).duosecurity.com"

        // Prepare query parameters
        let params: [String: String] = [
            "akey": akey,
            "fips_status": "1",
            "hsm_status": "true",
            "pkpush": "rsa-sha512"
        ]

        // Build URL with query parameters
        let urlString = "https://\(host)\(path)"
        guard var urlComponents = URLComponents(string: urlString) else {
            throw DuoAPIError.invalidURL
        }
        urlComponents.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = urlComponents.url else {
            throw DuoAPIError.invalidURL
        }

        let time = rfc2822Date()
        let signature = try generateSignature(method: "GET", host: host, path: path, time: time, params: params, privateKeyPEM: privateKeyPEM, pkey: pkey)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("DuoMobileApp/4.73.0.873.1 (arm64; iOS 18.1); Client: Foundation", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(signature, forHTTPHeaderField: "Authorization")
        request.setValue(time, forHTTPHeaderField: "x-duo-date")
        request.setValue(host, forHTTPHeaderField: "host")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw DuoAPIError.invalidResponse
        }

        verboseLog("[DuoPush] checkForPushRequests response: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseDict = json["response"] as? [String: Any],
              let transactionsArray = responseDict["transactions"] as? [[String: Any]] else {
            return []
        }

        var transactions: [PushTransaction] = []
        for txDict in transactionsArray {
            if let urgid = txDict["urgid"] as? String {
                // Verified Duo Push transactions carry a step_up_code_info block
                // describing how many digits the user must enter to approve.
                let stepUpInfo = txDict["step_up_code_info"] as? [String: Any]
                let stepUpNumDigits = stepUpInfo?["num_digits"] as? Int

                NSLog("[DuoPush] Found transaction: urgid=%@ verified=%@", urgid, stepUpNumDigits != nil ? "yes" : "no")
                transactions.append(PushTransaction(
                    urgid: urgid,
                    urgency: txDict["urgency"] as? String,
                    title: txDict["title"] as? String,
                    message: txDict["message"] as? String,
                    stepUpNumDigits: stepUpNumDigits,
                    summary: txDict["summary"] as? String,
                    type: txDict["type"] as? String,
                    attributeGroups: Self.parseAttributes(txDict["attributes"])
                ))
            }
        }

        return transactions
    }

    func respondToPush(key: DuoKey, urgid: String, approve: Bool, stepUpCode: String? = nil) async throws {
        guard let pkey = key.pkey, let akey = key.akey, let privateKeyPEM = key.privateKey else {
            throw DuoAPIError.missingPushCredentials
        }

        let path = "/push/v2/device/transactions/\(urgid)"
        let host = "\(key.host).duosecurity.com"
        let urlString = "https://\(host)\(path)"

        NSLog("[DuoPush] Responding to push: urgid=%@ host=%@ path=%@ action=%@", urgid, host, path, approve ? "approve" : "deny")

        guard let url = URL(string: urlString) else {
            throw DuoAPIError.invalidURL
        }

        // Prepare POST data
        var params: [String: String] = [
            "akey": akey,
            "answer": approve ? "approve" : "deny",
            "fips_status": "1",
            "hsm_status": "true",
            "pkpush": "rsa-sha512"
        ]

        // Verified Duo Push: the code the user read off the access device. Must be
        // added before signing, since the signature covers the sorted params.
        if approve, let stepUpCode = stepUpCode, !stepUpCode.isEmpty {
            params["step_up_code"] = stepUpCode
        }

        let time = rfc2822Date()
        let signature = try generateSignature(method: "POST", host: host, path: path, time: time, params: params, privateKeyPEM: privateKeyPEM, pkey: pkey)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("DuoMobileApp/4.73.0.873.1 (arm64; iOS 18.1); Client: Foundation", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(signature, forHTTPHeaderField: "Authorization")
        request.setValue(time, forHTTPHeaderField: "x-duo-date")
        request.setValue(host, forHTTPHeaderField: "host")
        request.setValue(urgid, forHTTPHeaderField: "txId")

        // Build form-encoded body with sorted params (must match signature)
        let sortedParams = params.sorted { $0.key < $1.key }
        let bodyString = sortedParams.map { "\($0.key)=\(urlEncode($0.value))" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)

        verboseLog("[DuoPush] Request URL: \(urlString)")
        verboseLog("[DuoPush] Request body: \(Self.redactStepUpCode(in: bodyString))")
        verboseLog("[DuoPush] Headers: Authorization=\(signature), x-duo-date=\(time), host=\(host), txId=\(urgid)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DuoAPIError.pushResponseFailed(details: "Invalid response type")
        }

        if httpResponse.statusCode != 200 {
            let responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode response"
            throw DuoAPIError.pushResponseFailed(details: "HTTP \(httpResponse.statusCode): \(responseBody)")
        }
    }

    /// Keeps verification codes out of the unified log. They are short-lived and
    /// single-use, but there is no reason to persist them to disk.
    static func redactStepUpCode(in string: String) -> String {
        guard let range = string.range(of: "step_up_code=") else { return string }
        let valueStart = range.upperBound
        let valueEnd = string[valueStart...].firstIndex(where: { $0 == "&" || $0 == "\n" }) ?? string.endIndex
        return string.replacingCharacters(in: valueStart..<valueEnd, with: "<redacted>")
    }

    private func rfc2822Date() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date())
    }

    private func generateSignature(method: String, host: String, path: String, time: String, params: [String: String], privateKeyPEM: String, pkey: String) throws -> String {
        // Build signature message: time + "\n" + method + "\n" + host + "\n" + path + "\n" + urlencode(params)
        let sortedParams = params.sorted { $0.key < $1.key }
        let encodedParams = sortedParams.map { "\($0.key)=\(urlEncode($0.value))" }.joined(separator: "&")
        let message = "\(time)\n\(method)\n\(host.lowercased())\n\(path)\n\(encodedParams)"

        verboseLog("[DuoPush] Signature message:\n\(Self.redactStepUpCode(in: message))")

        guard let messageData = message.data(using: .ascii) else {
            throw DuoAPIError.invalidResponse
        }

        // Sign with RSA SHA-512
        let signature = try signWithRSA(data: messageData, privateKeyPEM: privateKeyPEM)

        // Create auth header: Basic base64(pkey:base64(signature))
        let signatureBase64 = signature.base64EncodedString()
        let credentials = "\(pkey):\(signatureBase64)"
        guard let credentialsData = credentials.data(using: .ascii) else {
            throw DuoAPIError.invalidResponse
        }

        return "Basic \(credentialsData.base64EncodedString())"
    }

    private func signWithRSA(data: Data, privateKeyPEM: String) throws -> Data {
        // Remove PEM headers and decode base64
        let pemLines = privateKeyPEM.components(separatedBy: .newlines)
        let base64String = pemLines
            .filter { !$0.contains("BEGIN") && !$0.contains("END") && !$0.isEmpty }
            .joined()

        guard let keyData = Data(base64Encoded: base64String) else {
            throw DuoAPIError.keyExportFailed
        }

        // Create SecKey from private key data
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 2048
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else {
            throw DuoAPIError.keyExportFailed
        }

        // Sign with SHA-512
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA512,
            data as CFData,
            &error
        ) as Data? else {
            throw DuoAPIError.keyExportFailed
        }

        return signature
    }

    private func base32Encode(_ data: Data) -> String {
        let base32Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        var bits = ""

        // Convert data to binary string
        for byte in data {
            bits += String(byte, radix: 2).leftPadding(toLength: 8, withPad: "0")
        }

        // Pad to multiple of 5 bits
        while bits.count % 5 != 0 {
            bits += "0"
        }

        // Convert 5-bit groups to base32 characters
        var result = ""
        for i in stride(from: 0, to: bits.count, by: 5) {
            let index = Int(String(bits.dropFirst(i).prefix(5)), radix: 2)!
            let char = base32Alphabet[base32Alphabet.index(base32Alphabet.startIndex, offsetBy: index)]
            result.append(char)
        }

        // Add padding
        while result.count % 8 != 0 {
            result += "="
        }

        return result
    }
}

enum DuoAPIError: LocalizedError {
    case invalidURL
    case activationFailed
    case invalidResponse
    case keyGenerationFailed
    case keyExportFailed
    case missingPushCredentials
    case pushResponseFailed(details: String)
    case invalidStepUpCode(expectedDigits: Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid activation URL"
        case .activationFailed:
            return "Activation failed"
        case .invalidResponse:
            return "Invalid response from Duo"
        case .keyGenerationFailed:
            return "Failed to generate RSA key pair"
        case .keyExportFailed:
            return "Failed to export RSA key"
        case .missingPushCredentials:
            return "Push credentials (pkey/akey) not available"
        case .pushResponseFailed(let details):
            return "Push response failed: \(details)"
        case .invalidStepUpCode(let expectedDigits):
            return "This is a Verified Duo Push. Enter the \(expectedDigits)-digit code shown on the device you are logging in from."
        }
    }
}
