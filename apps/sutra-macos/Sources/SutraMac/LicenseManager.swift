import Foundation
import IOKit
import CommonCrypto

public final class LicenseManager {
    public static let shared = LicenseManager()

    // Canonical master salt used for HMAC-SHA256 device key generation
    public static let masterSalt = "SUTRA_SOVEREIGN_2026_MASTER_SECRET_SALT_ARIADNE"

    private static let licensePath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.sutra/.license"
    }()

    public init() {}

    /// Extracts macOS Hardware UUID via native IOKit registry
    public func getHardwareUUID() -> String {
        let platformExpert = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard platformExpert != 0 else { return "UNKNOWN-DEVICE-UUID" }
        defer { IOObjectRelease(platformExpert) }

        if let uuidProperty = IORegistryEntryCreateCFProperty(platformExpert, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
            return uuidProperty.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
        return "UNKNOWN-DEVICE-UUID"
    }

    /// Computes user-facing readable Device ID (e.g., SUTRA-9B4F-28A1)
    public func getDeviceID() -> String {
        let rawUUID = getHardwareUUID()
        let digest = sha256("DEVICE:\(rawUUID)")
        let prefix = String(digest.prefix(8)).uppercased()
        let p1 = String(prefix.prefix(4))
        let p2 = String(prefix.suffix(4))
        return "SUTRA-\(p1)-\(p2)"
    }

    /// Generates canonical 8-character activation code for a given device ID
    public static func computeActivationCode(for deviceID: String) -> String {
        let cleanID = deviceID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let payload = "\(cleanID):\(masterSalt)"
        let digest = sha256Static(payload)
        let rawCode = String(digest.prefix(8)).uppercased()
        let c1 = String(rawCode.prefix(4))
        let c2 = String(rawCode.suffix(4))
        return "\(c1)-\(c2)"
    }

    /// Verifies if an entered code is valid for this machine
    public func verify(code: String) -> Bool {
        let cleanInput = code.replacingOccurrences(of: "-", with: "")
                             .replacingOccurrences(of: " ", with: "")
                             .trimmingCharacters(in: .whitespacesAndNewlines)
                             .uppercased()
        let expected = Self.computeActivationCode(for: getDeviceID())
                           .replacingOccurrences(of: "-", with: "")
        return cleanInput == expected
    }

    /// Checks if this Mac is currently activated
    public func isActivated() -> Bool {
        guard FileManager.default.fileExists(atPath: Self.licensePath) else { return false }
        guard let savedCode = try? String(contentsOfFile: Self.licensePath, encoding: .utf8) else { return false }
        return verify(code: savedCode)
    }

    /// Activates and persists the license to disk
    @discardableResult
    public func activate(with code: String) -> Bool {
        if verify(code: code) {
            let dir = (Self.licensePath as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let formatted = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            try? formatted.write(toFile: Self.licensePath, atomically: true, encoding: .utf8)
            return true
        }
        return false
    }

    /// Online activation via Cloudflare Worker Licensing Gateway
    public func activateOnline(email: String, endpoint: String = "https://sutra-licensing.workers.dev", completion: @escaping (Bool, String) -> Void) {
        guard let url = URL(string: "\(endpoint)/api/activate") else {
            completion(false, "Invalid licensing endpoint")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 8.0

        let payload: [String: Any] = [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            "deviceId": getDeviceID()
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(false, "Failed to encode activation payload")
            return
        }
        request.httpBody = bodyData

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                completion(false, "Network error: \(error.localizedDescription)")
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(false, "Invalid response from licensing gateway")
                return
            }

            let status = json["status"] as? String ?? ""
            if status == "active" {
                if let code = json["code"] as? String, self?.activate(with: code) == true {
                    completion(true, "Device activated successfully")
                    return
                }
            }

            let msg = json["message"] as? String ?? "Account not whitelisted. Contact Ramesh for access."
            completion(false, msg)
        }.resume()
    }

    /// Sends an idempotent background telemetry heartbeat once connected to the internet
    public func sendHeartbeatIfNeeded(endpoint: String = "https://sutra-licensing.workers.dev") {
        let metaPath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.sutra/.license_meta"
        let now = Date().timeIntervalSince1970
        
        // Rate-limit heartbeats to at most once per 6 hours
        if let metaStr = try? String(contentsOfFile: metaPath, encoding: .utf8),
           let lastPing = Double(metaStr.trimmingCharacters(in: .whitespacesAndNewlines)),
           (now - lastPing) < 21600 {
            return
        }

        guard let url = URL(string: "\(endpoint)/api/heartbeat") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 5.0

        let payload: [String: Any] = [
            "deviceId": getDeviceID(),
            "email": NSUserName(),
            "appVersion": "1.0.0",
            "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
            "offlineActivated": false
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        req.httpBody = body

        URLSession.shared.dataTask(with: req) { _, _, error in
            if error == nil {
                try? "\(now)".write(toFile: metaPath, atomically: true, encoding: .utf8)
            }
        }.resume()
    }

    /// Submits non-sensitive diagnostic logs to Cloudflare edge for troubleshooting
    public func submitDiagnosticLogs(description: String, endpoint: String = "https://sutra-licensing.workers.dev", completion: @escaping (Bool, String) -> Void) {
        guard let url = URL(string: "\(endpoint)/api/logs") else {
            completion(false, "Invalid endpoint")
            return
        }

        var errLogs = ""
        if let data = try? Data(contentsOf: URL(fileURLWithPath: "/tmp/sutra.err")),
           let str = String(data: data, encoding: .utf8) {
            errLogs = str
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "deviceId": getDeviceID(),
            "email": NSUserName(),
            "appVersion": "1.0.0",
            "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
            "description": description,
            "logs": errLogs.suffix(4000)
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(false, "Encoding error")
            return
        }
        req.httpBody = body

        URLSession.shared.dataTask(with: req) { data, _, error in
            if let error = error {
                completion(false, error.localizedDescription)
                return
            }
            completion(true, "Diagnostic logs submitted successfully.")
        }.resume()
    }

    private func sha256(_ string: String) -> String {
        return Self.sha256Static(string)
    }

    private static func sha256Static(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else { return "" }
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
