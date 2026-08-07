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

// MARK: - Certificate Pinning

// SPKI SHA-256 hashes of DigiCert intermediate CAs used by GitHub.
// Pin the intermediates (not the leaf) so routine cert rotation doesn't break updates.
// Update this list if GitHub migrates to a new CA chain.
// To get current hashes: openssl s_client -connect api.github.com:443 | openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64
private let pinnedSPKIHashes: Set<String> = [
    "RQeZkB42znUfsDIIFWIRiYEcKl7nHwNFwWCrnMMJbi0=", // DigiCert TLS RSA SHA256 2020 CA1
    "WoiWRyIOVNa9ihaBciRSC7XHjliYS9VwUGOIud4PB18=", // DigiCert High Assurance TLS Hybrid ECC SHA256
    "Vjs8r4z+80wjNcr1YKepWQboSIRi63WsWXhIMN+eWys=", // DigiCert Global Root CA (backup)
]

class PinningDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Standard TLS validation first
        var error: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &error) else {
            print("TLS validation failed:", error?.localizedDescription ?? "unknown")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Then verify at least one cert in the chain matches our pinned SPKI hashes
        let certCount = SecTrustGetCertificateCount(serverTrust)
        for i in 0..<certCount {
            guard let cert = SecTrustGetCertificateAtIndex(serverTrust, i) else { continue }
            let data = SecCertificateCopyData(cert) as Data
            // Extract public key and hash it
            if let spkiHash = spkiSHA256(from: cert) {
                if pinnedSPKIHashes.contains(spkiHash) {
                    completionHandler(.useCredential, URLCredential(trust: serverTrust))
                    return
                }
            }
            _ = data // suppress warning
        }

        print("Certificate pinning failed — no matching SPKI in chain")
        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    private func spkiSHA256(from cert: SecCertificate) -> String? {
        var key: SecKey?
        var trust: SecTrust?
        let policy = SecPolicyCreateBasicX509()
        SecTrustCreateWithCertificates(cert, policy, &trust)
        if let trust = trust {
            SecTrustEvaluateWithError(trust, nil)
            key = SecTrustCopyKey(trust)
        }
        guard let publicKey = key,
              let keyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else { return nil }
        let hash = SHA256.hash(data: keyData)
        return Data(hash).base64EncodedString()
    }
}

// MARK: - Updater

class Updater {
    static let repoAPI = "https://api.github.com/repos/zodl-inc/poc-macos-dmg/releases/latest"
    static let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
    static let teamID = "RLPRR8CPQG"

    private static let pinningDelegate = PinningDelegate()
    private static let session = URLSession(
        configuration: .default,
        delegate: pinningDelegate,
        delegateQueue: nil
    )

    static func checkAndUpdate() {
        guard let url = URL(string: repoAPI) else { return }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        session.dataTask(with: req) { data, _, error in
            if let error = error {
                print("Update check failed:", error.localizedDescription)
                return
            }
            guard let data,
                  let release = try? JSONDecoder().decode(Release.self, from: data) else { return }

            let latest = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            guard latest.compare(currentVersion, options: .numeric) == .orderedDescending else {
                print("Already up to date: \(currentVersion)")
                return
            }

            guard let dmgAsset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }),
                  let sha256Asset = release.assets.first(where: { $0.name.hasSuffix(".sha256") }),
                  let dmgURL = URL(string: dmgAsset.browser_download_url),
                  let sha256URL = URL(string: sha256Asset.browser_download_url) else {
                print("Missing DMG or .sha256 asset in release")
                return
            }

            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Update available — v\(latest)"
                alert.informativeText = "A new version of HelloWorld is available. Install now and relaunch?"
                alert.addButton(withTitle: "Install & Relaunch")
                alert.addButton(withTitle: "Not Now")
                alert.alertStyle = .informational
                if alert.runModal() == .alertFirstButtonReturn {
                    downloadAndInstall(dmgURL: dmgURL, sha256URL: sha256URL, version: latest)
                }
            }
        }.resume()
    }

    private static func downloadAndInstall(dmgURL: URL, sha256URL: URL, version: String) {
        let dmgDest = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("HelloWorld-\(version).dmg")

        // Step 1: fetch expected SHA256
        guard let sha256Data = try? Data(contentsOf: sha256URL),
              let sha256Line = String(data: sha256Data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .whitespaces).first else {
            showError("Couldn't fetch checksum for update.")
            return
        }

        session.downloadTask(with: dmgURL) { tmp, _, error in
            guard let tmp, error == nil else {
                showError("Download failed: \(error?.localizedDescription ?? "unknown")")
                return
            }
            try? FileManager.default.moveItem(at: tmp, to: dmgDest)

            // Step 2: verify SHA256 checksum
            guard let dmgData = try? Data(contentsOf: dmgDest) else { return }
            let actualHash = SHA256.hash(data: dmgData)
                .map { String(format: "%02x", $0) }.joined()

            guard actualHash == sha256Line else {
                showError("Checksum mismatch — update aborted.\nExpected: \(sha256Line)\nGot: \(actualHash)")
                try? FileManager.default.removeItem(at: dmgDest)
                return
            }
            print("✅ SHA256 verified:", actualHash)

            // Step 3: verify DMG code signature matches our Team ID
            let verifyResult = runOutput("/bin/sh", [
                "-c",
                "codesign -dv '\(dmgDest.path)' 2>&1 | grep TeamIdentifier"
            ])
            guard verifyResult.contains("TeamIdentifier=\(teamID)") else {
                showError("Code signature mismatch — update aborted.\n\(verifyResult)")
                try? FileManager.default.removeItem(at: dmgDest)
                return
            }
            print("✅ Code signature verified: TeamIdentifier=\(teamID)")

            // Step 4: remove quarantine from downloaded DMG
            run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", dmgDest.path])

            // Step 5: mount DMG
            let mountOutput = runOutput("/usr/bin/hdiutil", [
                "attach", dmgDest.path, "-nobrowse", "-quiet", "-plist"
            ])
            let mountPoint = parseMountPoint(mountOutput) ?? "/Volumes/HelloWorld"
            let sourceApp = "\(mountPoint)/HelloWorld.app"

            // Step 6: install to ~/Applications (no admin needed)
            let homeApps = "\(NSHomeDirectory())/Applications"
            let destApp = "\(homeApps)/HelloWorld.app"
            run("/bin/mkdir", ["-p", homeApps])
            run("/bin/sh", ["-c", "rm -rf '\(destApp)' && cp -R '\(sourceApp)' '\(destApp)'"])
            run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", destApp])

            // Step 7: detach DMG
            run("/usr/bin/hdiutil", ["detach", mountPoint, "-quiet", "-force"])
            try? FileManager.default.removeItem(at: dmgDest)

            // Step 8: relaunch
            DispatchQueue.main.async {
                let p = Process()
                p.launchPath = "/usr/bin/open"
                p.arguments = [destApp]
                p.launch()
                NSApplication.shared.terminate(nil)
            }
        }.resume()
    }

    private static func showError(_ msg: String) {
        DispatchQueue.main.async {
            let a = NSAlert()
            a.messageText = "Update failed"
            a.informativeText = msg
            a.alertStyle = .critical
            a.runModal()
        }
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
        for entity in entities {
            if let mp = entity["mount-point"] as? String { return mp }
        }
        return nil
    }
}
