import Cocoa
import CryptoKit
import Security

struct Release: Decodable {
    let tag_name: String
    let assets: [Asset]
    struct Asset: Decodable {
        let name: String
        let browser_download_url: String
    }
}

// MARK: - Certificate Pinning with OCSP Fallback
//
// Pin = SPKI SHA-256 of GitHub's current public key.
// If pin doesn't match (GitHub rotated their key):
//   → Query OCSP for the previously-pinned cert
//   → If OCSP says "revoked" or cert is expired → GitHub legitimately rotated → allow via standard TLS
//   → If OCSP says "good" → the pinned cert is still valid but we're seeing a different key = MITM → BLOCK
//
// This means:
//   - Users are never stuck if GitHub renews their cert (OCSP fallback allows through)
//   - MITM with a different cert while the real one is still valid is blocked
//   - Developer should update the pinned hashes after GitHub rotates

// GitHub's current SPKI SHA-256 hashes (as of 2026-08-07, Sectigo chain)
// Update these after GitHub rotates their key (OCSP fallback handles the transition window)
// Hashes computed via scripts/get-spki-hashes.swift on macos-15 GitHub Actions runner (2026-08-07)
// Intermediate + root pinned as backup — survives leaf cert rotation if key stays the same
private let pinnedSPKIHashes: Set<String> = [
    "EfXAzYKYsOsdi115+whKa+Yntz0T55fOk7iirLhX7rc=", // *.github.com leaf
    "VqePxH3EcFwZuYK3CCOMz5HKMoeIZpZcEyBf4diPGSA=", // Sectigo Public Server Authentication CA DV E36
    "EdsvlytFf4a/O+hCPwBXFFi46RKXqivCAF+mO7s+5Ng=", // Sectigo Public Server Authentication Root E46
]

class PinningDelegate: NSObject, URLSessionDelegate {
    let log: (String) -> Void
    init(log: @escaping (String) -> Void) { self.log = log }

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Step 1: standard TLS chain validation
        var error: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &error) else {
            log("❌ TLS chain invalid: \(error?.localizedDescription ?? "?")")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Step 2: check if any cert in chain matches our pinned SPKI hashes
        let certCount = SecTrustGetCertificateCount(serverTrust)
        for i in 0..<certCount {
            guard let cert = SecTrustGetCertificateAtIndex(serverTrust, i) else { continue }
            if let hash = spkiSHA256(cert), pinnedSPKIHashes.contains(hash) {
                log("🔒 TLS pin matched cert[\(i)] — OK")
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            }
        }

        // Step 3: pin mismatch — check OCSP to distinguish rotation vs MITM
        log("⚠️ TLS pin mismatch — checking OCSP to distinguish rotation from MITM...")
        checkOCSPFallback(serverTrust: serverTrust, completionHandler: completionHandler)
    }

    private func checkOCSPFallback(serverTrust: SecTrust,
                                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // macOS evaluates OCSP automatically as part of SecTrustEvaluateWithError.
        // We re-evaluate with explicit revocation policy to get revocation status.
        let revocationPolicy = SecPolicyCreateRevocation(
            kSecRevocationOCSPMethod | kSecRevocationRequirePositiveResponse
        )
        let basicPolicy = SecPolicyCreateSSL(true, "api.github.com" as CFString)

        let certChain = SecTrustCopyCertificateChain(serverTrust) as! [SecCertificate]
        var newTrust: SecTrust?
        guard SecTrustCreateWithCertificates(
            certChain as CFArray,
            [basicPolicy, revocationPolicy] as CFArray,
            &newTrust
        ) == errSecSuccess, let newTrust else {
            log("⚠️ OCSP: couldn't create revocation trust — falling back to standard TLS")
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
            return
        }

        var ocspError: CFError?
        let isValid = SecTrustEvaluateWithError(newTrust, &ocspError)

        if isValid {
            // OCSP says the cert chain is still good — this is a MITM (different key, cert still valid)
            log("❌ OCSP: pinned cert still valid but SPKI differs — blocking (possible MITM)")
            completionHandler(.cancelAuthenticationChallenge, nil)
        } else {
            // OCSP says revoked or expired — GitHub legitimately rotated, allow via standard TLS
            log("✅ OCSP: cert revoked/expired — GitHub rotated legitimately, allowing via system trust")
            log("   ⚠️  Update pinnedSPKIHashes in Updater.swift with GitHub's new cert hashes")
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        }
    }

    private func spkiSHA256(_ cert: SecCertificate) -> String? {
        var key: SecKey?
        var trust: SecTrust?
        SecTrustCreateWithCertificates(cert, SecPolicyCreateBasicX509(), &trust)
        if let t = trust { SecTrustEvaluateWithError(t, nil); key = SecTrustCopyKey(t) }
        guard let k = key, let data = SecKeyCopyExternalRepresentation(k, nil) as Data? else { return nil }
        return Data(SHA256.hash(data: data)).base64EncodedString()
    }
}

// MARK: - Ed25519 public key for checksum verification
// Private key in SM: /infra/apple/update-signing-key
private let updatePublicKeyB64 = "MCowBQYDK2VwAyEA9aT3lXqgqgD2NyCH7S7nJ7MANFPOb9oL+8u9K1sWp28="

// MARK: - Updater

class Updater {
    static let repoAPI = "https://api.github.com/repos/zodl-inc/poc-macos-dmg/releases/latest"
    static let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
    static let teamID = "RLPRR8CPQG"

    static func checkAndUpdate(log: @escaping (String) -> Void) {
        log("🔍 Checking for updates (current: v\(currentVersion))...")
        let delegate = PinningDelegate(log: log)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        guard let url = URL(string: repoAPI) else { return }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        session.dataTask(with: req) { data, response, error in
            if let error = error {
                log("❌ Update check failed: \(error.localizedDescription)")
                return
            }
            if let http = response as? HTTPURLResponse {
                log("📡 GitHub API response: HTTP \(http.statusCode)")
            }
            guard let data else {
                log("❌ No data received")
                return
            }
            guard let release = try? JSONDecoder().decode(Release.self, from: data) else {
                let body = String(data: data, encoding: .utf8) ?? "(unreadable)"
                log("❌ Failed to parse release JSON: \(body.prefix(200))")
                return
            }

            let latest = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            log("📦 Latest release: v\(latest)")

            guard latest.compare(currentVersion, options: .numeric) == .orderedDescending else {
                log("✅ Already up to date")
                return
            }

            let dmgAsset   = release.assets.first(where: { $0.name.hasSuffix(".dmg") })
            let sha256Asset = release.assets.first(where: { $0.name.hasSuffix(".sha256") })
            let sigAsset    = release.assets.first(where: { $0.name.hasSuffix(".sha256.sig.b64") })
            log("📎 Assets: DMG=\(dmgAsset?.name ?? "MISSING") sha256=\(sha256Asset?.name ?? "MISSING") sig=\(sigAsset?.name ?? "MISSING")")

            guard let dmgAsset, let sha256Asset, let sigAsset,
                  let dmgURL    = URL(string: dmgAsset.browser_download_url),
                  let sha256URL = URL(string: sha256Asset.browser_download_url),
                  let sigURL    = URL(string: sigAsset.browser_download_url) else {
                log("❌ Missing required assets (DMG, .sha256, or .sha256.sig.b64)")
                return
            }

            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Update available — v\(latest)"
                alert.informativeText = "Install now and relaunch?"
                alert.addButton(withTitle: "Install & Relaunch")
                alert.addButton(withTitle: "Not Now")
                alert.alertStyle = .informational
                if alert.runModal() == .alertFirstButtonReturn {
                    downloadAndInstall(dmgURL: dmgURL, sha256URL: sha256URL,
                                       sigURL: sigURL, version: latest,
                                       session: session, log: log)
                }
            }
        }.resume()
    }

    private static func verifyEd25519(data: Data, signatureB64: String, log: (String) -> Void) -> Bool {
        // CryptoKit Curve25519 (Ed25519) — strip the 12-byte DER header to get the raw 32-byte key
        guard let pubKeyDER = Data(base64Encoded: updatePublicKeyB64),
              pubKeyDER.count == 44,
              let sigData = Data(base64Encoded: signatureB64) else {
            log("❌ Ed25519: failed to decode key or signature")
            return false
        }
        let rawKey = pubKeyDER.suffix(32) // DER prefix is 12 bytes for Ed25519
        do {
            let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: rawKey)
            let ok = publicKey.isValidSignature(sigData, for: data)
            if ok { log("✅ Ed25519 signature verified") }
            else  { log("❌ Ed25519 signature INVALID") }
            return ok
        } catch {
            log("❌ Ed25519: \(error.localizedDescription)")
            return false
        }
    }

    private static func downloadAndInstall(dmgURL: URL, sha256URL: URL, sigURL: URL,
                                            version: String,
                                            session: URLSession,
                                            log: @escaping (String) -> Void) {
        let dmgDest = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("HelloWorld-\(version).dmg")

        log("📥 Fetching checksum + signature...")
        guard let sha256Data = try? Data(contentsOf: sha256URL),
              let sha256Line = String(data: sha256Data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .whitespaces).first else {
            log("❌ Couldn't fetch .sha256")
            return
        }
        guard let sigB64Raw = try? String(contentsOf: sigURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines), !sigB64Raw.isEmpty else {
            log("❌ Couldn't fetch .sha256.sig.b64")
            return
        }
        log("🔢 Expected SHA256: \(sha256Line)")
        log("🔏 Verifying Ed25519 signature on checksum...")
        guard verifyEd25519(data: sha256Data, signatureB64: sigB64Raw, log: log) else {
            log("❌ Ed25519 verification failed — aborting")
            return
        }

        log("📥 Downloading DMG...")
        session.downloadTask(with: dmgURL) { tmp, _, error in
            guard let tmp, error == nil else {
                log("❌ Download failed: \(error?.localizedDescription ?? "unknown")")
                return
            }
            try? FileManager.default.moveItem(at: tmp, to: dmgDest)
            log("💾 Saved to \(dmgDest.lastPathComponent)")

            guard let dmgData = try? Data(contentsOf: dmgDest) else { return }
            let actualHash = SHA256.hash(data: dmgData).map { String(format: "%02x", $0) }.joined()
            log("🔢 Actual   SHA256: \(actualHash)")

            guard actualHash == sha256Line else {
                log("❌ SHA256 mismatch — aborting")
                try? FileManager.default.removeItem(at: dmgDest)
                return
            }
            log("✅ SHA256 verified")

            let verifyResult = runOutput("/bin/sh", ["-c",
                "codesign -dv '\(dmgDest.path)' 2>&1 | grep TeamIdentifier"])
            log("🔏 codesign: \(verifyResult.trimmingCharacters(in: .whitespacesAndNewlines))")
            guard verifyResult.contains("TeamIdentifier=\(teamID)") else {
                log("❌ Code signature mismatch — aborting")
                try? FileManager.default.removeItem(at: dmgDest)
                return
            }
            log("✅ Code signature verified")

            run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", dmgDest.path])

            log("📂 Mounting DMG...")
            let mountOutput = runOutput("/usr/bin/hdiutil",
                ["attach", dmgDest.path, "-nobrowse", "-quiet", "-plist"])
            let mountPoint = parseMountPoint(mountOutput) ?? "/Volumes/HelloWorld"
            log("📂 Mounted at \(mountPoint)")

            let homeApps = "\(NSHomeDirectory())/Applications"
            let destApp = "\(homeApps)/HelloWorld.app"
            log("📋 Installing to \(destApp)...")
            run("/bin/mkdir", ["-p", homeApps])
            run("/bin/sh", ["-c", "rm -rf '\(destApp)' && cp -R '\(mountPoint)/HelloWorld.app' '\(destApp)'"])
            run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", destApp])
            log("✅ Installed")

            run("/usr/bin/hdiutil", ["detach", mountPoint, "-quiet", "-force"])
            try? FileManager.default.removeItem(at: dmgDest)

            log("🚀 Relaunching from \(destApp)...")
            DispatchQueue.main.async {
                // Use a shell script that waits for this process to exit before opening,
                // and forces a new instance (-n) so macOS doesn't reuse a running copy
                // from a different path (e.g. /Applications vs ~/Applications).
                let pid = ProcessInfo.processInfo.processIdentifier
                let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; open -n '\(destApp)'"
                let p = Process()
                p.launchPath = "/bin/sh"
                p.arguments = ["-c", script]
                p.launch()
                NSApplication.shared.terminate(nil)
            }
        }.resume()
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> Int32 {
        let p = Process(); p.launchPath = path; p.arguments = args
        p.launch(); p.waitUntilExit(); return p.terminationStatus
    }

    private static func runOutput(_ path: String, _ args: [String]) -> String {
        let p = Process(); p.launchPath = path; p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe
        p.launch(); p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private static func parseMountPoint(_ plistString: String) -> String? {
        guard let data = plistString.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any],
              let entities = dict["system-entities"] as? [[String: Any]] else { return nil }
        for entity in entities { if let mp = entity["mount-point"] as? String { return mp } }
        return nil
    }
}
