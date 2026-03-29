import Foundation
import Security

/// Loads the API key from the macOS Keychain or environment.
/// Reused from PartsStudio -- reads keys stored by `parts auth login`.
enum APIKeychain {
    private static var cachedKey: String?

    static func clearCache() {
        cachedKey = nil
    }

    static func loadAPIKey() -> String? {
        if let cached = cachedKey {
            return cached
        }

        if let envKey = ProcessInfo.processInfo.environment["PARTS_API_KEY"], !envKey.isEmpty {
            cachedKey = envKey
            return envKey
        }

        for account in ["api-key", "oauth-access-token"] {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            proc.arguments = ["find-generic-password", "-s", "parts-cli", "-a", account, "-w"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()

            do {
                try proc.run()
                proc.waitUntilExit()
                guard proc.terminationStatus == 0 else { continue }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !raw.isEmpty else { continue }

                let key: String
                if raw.hasPrefix("go-keyring-base64:") {
                    let encoded = String(raw.dropFirst("go-keyring-base64:".count))
                    if let decoded = Data(base64Encoded: encoded),
                       let token = String(data: decoded, encoding: .utf8), !token.isEmpty {
                        key = token
                    } else {
                        continue
                    }
                } else {
                    key = raw
                }
                cachedKey = key
                return key
            } catch {
                continue
            }
        }

        return nil
    }
}
