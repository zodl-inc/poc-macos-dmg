import Cocoa

struct Release: Decodable {
    let tag_name: String
    let assets: [Asset]
    struct Asset: Decodable {
        let name: String
        let browser_download_url: String
    }
}

class Updater {
    static let repoAPI = "https://api.github.com/repos/zodl-inc/poc-macos-dmg/releases/latest"
    static let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String

    static func checkAndUpdate() {
        guard let url = URL(string: repoAPI) else { return }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data,
                  let release = try? JSONDecoder().decode(Release.self, from: data) else { return }

            let latest = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            guard latest.compare(currentVersion, options: .numeric) == .orderedDescending else {
                print("Already up to date: \(currentVersion)")
                return
            }

            guard let dmgAsset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }),
                  let dmgURL = URL(string: dmgAsset.browser_download_url) else { return }

            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Update available — v\(latest)"
                alert.informativeText = "A new version of HelloWorld is available. Install now and relaunch?"
                alert.addButton(withTitle: "Install & Relaunch")
                alert.addButton(withTitle: "Not Now")
                alert.alertStyle = .informational
                if alert.runModal() == .alertFirstButtonReturn {
                    downloadAndInstall(dmgURL: dmgURL, version: latest)
                }
            }
        }.resume()
    }

    private static func downloadAndInstall(dmgURL: URL, version: String) {
        let dmgDest = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("HelloWorld-\(version).dmg")

        URLSession.shared.downloadTask(with: dmgURL) { tmp, _, _ in
            guard let tmp else { return }
            try? FileManager.default.moveItem(at: tmp, to: dmgDest)

            // Remove quarantine from the downloaded DMG first
            run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", dmgDest.path])

            // Mount DMG (no auto-open, no browse)
            let mountOutput = runOutput("/usr/bin/hdiutil", [
                "attach", dmgDest.path, "-nobrowse", "-quiet", "-plist"
            ])

            // Parse mount point from plist output
            let mountPoint = parseMountPoint(mountOutput) ?? "/Volumes/HelloWorld"
            let sourceApp = "\(mountPoint)/HelloWorld.app"
            let homeApps = "\(NSHomeDirectory())/Applications"
            let destApp = "\(homeApps)/HelloWorld.app"

            // Install to ~/Applications (no admin password needed)
            run("/bin/mkdir", ["-p", homeApps])
            run("/bin/sh", ["-c", "rm -rf '\(destApp)' && cp -R '\(sourceApp)' '\(destApp)'"])
            run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", destApp])

            // Detach DMG
            run("/usr/bin/hdiutil", ["detach", mountPoint, "-quiet", "-force"])

            // Relaunch
            DispatchQueue.main.async {
                let p = Process()
                p.launchPath = "/usr/bin/open"
                p.arguments = [destApp]
                p.launch()
                NSApplication.shared.terminate(nil)
            }
        }.resume()
    }

    // Run a process and discard output
    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.launchPath = path
        p.arguments = args
        p.launch()
        p.waitUntilExit()
        return p.terminationStatus
    }

    // Run a process and capture stdout
    private static func runOutput(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.launchPath = path
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.launch()
        p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    // Parse hdiutil -plist output to find the actual mount point
    private static func parseMountPoint(_ plistString: String) -> String? {
        guard let data = plistString.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any],
              let entities = dict["system-entities"] as? [[String: Any]] else { return nil }
        for entity in entities {
            if let mountPoint = entity["mount-point"] as? String {
                return mountPoint
            }
        }
        return nil
    }
}
