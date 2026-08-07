import Foundation

// Minimal self-updater — polls a static JSON on GitHub, downloads DMG, installs, relaunches.
// Drop Sparkle in Info.plist (SUFeedURL) instead of this for production.
// This is for understanding how it works without a framework.

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

            print("New version \(latest) available")
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
        let dest = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("HelloWorld-\(version).dmg")

        URLSession.shared.downloadTask(with: dmgURL) { tmp, _, _ in
            guard let tmp else { return }
            try? FileManager.default.moveItem(at: tmp, to: dest)

            // Mount DMG
            let mount = Process()
            mount.launchPath = "/usr/bin/hdiutil"
            mount.arguments = ["attach", dest.path, "-nobrowse", "-quiet"]
            mount.launch(); mount.waitUntilExit()

            // Find mount point
            let mountPoint = "/Volumes/HelloWorld"
            let sourceApp = "\(mountPoint)/HelloWorld.app"
            let destApp = "/Applications/HelloWorld.app"

            // Replace app (requires no sandbox — see README)
            let install = Process()
            install.launchPath = "/bin/sh"
            install.arguments = ["-c", "rm -rf '\(destApp)' && cp -R '\(sourceApp)' '\(destApp)'"]
            install.launch(); install.waitUntilExit()

            // Detach DMG
            let detach = Process()
            detach.launchPath = "/usr/bin/hdiutil"
            detach.arguments = ["detach", mountPoint, "-quiet"]
            detach.launch(); detach.waitUntilExit()

            // Relaunch new version
            DispatchQueue.main.async {
                let relaunch = Process()
                relaunch.launchPath = "/usr/bin/open"
                relaunch.arguments = [destApp]
                relaunch.launch()
                NSApplication.shared.terminate(nil)
            }
        }.resume()
    }
}
