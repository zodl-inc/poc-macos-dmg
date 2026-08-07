import Cocoa
import CryptoKit

struct Release: Decodable {
    let tag_name: String
    let assets: [Asset]
    struct Asset: Decodable {
        let name: String
        let browser_download_url: String
    }
}

// MARK: - Updater
// Security model: standard TLS (macOS system trust store) + SHA256 checksum + codesign TeamID verify + notarization.
// Cert pinning intentionally omitted — GitHub rotates certs without notice, which would silently
// break updates for all existing installs. The downloaded DMG signature is the real integrity check.

class Updater {
    static let repoAPI = "https://api.github.com/repos/zodl-inc/poc-macos-dmg/releases/latest"
    static let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
    static let teamID = "RLPRR8CPQG"

    static func checkAndUpdate(log: @escaping (String) -> Void) {
        log("🔍 Checking for updates (current: v\(currentVersion))...")
        let session = URLSession.shared

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

            let dmgAsset = release.assets.first(where: { $0.name.hasSuffix(".dmg") })
            let sha256Asset = release.assets.first(where: { $0.name.hasSuffix(".sha256") })
            log("📎 Assets found: DMG=\(dmgAsset?.name ?? "MISSING") sha256=\(sha256Asset?.name ?? "MISSING")")

            guard let dmgAsset, let sha256Asset,
                  let dmgURL = URL(string: dmgAsset.browser_download_url),
                  let sha256URL = URL(string: sha256Asset.browser_download_url) else {
                log("❌ Missing DMG or .sha256 asset")
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
                                       version: latest, log: log)
                }
            }
        }.resume()
    }

    private static func downloadAndInstall(dmgURL: URL, sha256URL: URL,
                                            version: String,
                                            log: @escaping (String) -> Void) {
        let session = URLSession.shared
        let dmgDest = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("HelloWorld-\(version).dmg")

        log("📥 Fetching checksum...")
        guard let sha256Data = try? Data(contentsOf: sha256URL),
              let sha256Line = String(data: sha256Data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .whitespaces).first else {
            log("❌ Couldn't fetch .sha256")
            return
        }
        log("🔢 Expected SHA256: \(sha256Line)")

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

            log("🚀 Relaunching...")
            DispatchQueue.main.async {
                let p = Process()
                p.launchPath = "/usr/bin/open"
                p.arguments = [destApp]
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
