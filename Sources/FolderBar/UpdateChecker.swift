import AppKit

/// Checks GitHub Releases for a newer tag and, if one exists, offers a
/// direct link to the release's downloadable asset — no silent background
/// install, no signing/appcast infrastructure, just "here's a newer build,
/// go get it" (NSWorkspace.open on the asset URL).
enum UpdateChecker {
    private static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/EdiBianco/folderbar-mac/releases/latest"
    )!

    static func checkForUpdates() {
        URLSession.shared.dataTask(with: latestReleaseURL) { data, _, error in
            guard
                let data, error == nil,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let tagName = json["tag_name"] as? String,
                let assets = json["assets"] as? [[String: Any]],
                let downloadURL = assets.first?["browser_download_url"] as? String
            else {
                DispatchQueue.main.async { presentCheckFailed() }
                return
            }

            let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

            DispatchQueue.main.async {
                if latestVersion.isNewer(than: currentVersion) {
                    presentUpdateAvailable(version: latestVersion, downloadURL: downloadURL)
                } else {
                    presentUpToDate()
                }
            }
        }.resume()
    }

    private static func presentUpdateAvailable(version: String, downloadURL: String) {
        let alert = NSAlert()
        alert.messageText = "FolderBar \(version) is available"
        alert.informativeText = "You're running an older version."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn, let url = URL(string: downloadURL) {
            NSWorkspace.shared.open(url)
        }
    }

    private static func presentUpToDate() {
        let alert = NSAlert()
        alert.messageText = "You're up to date"
        alert.runModal()
    }

    private static func presentCheckFailed() {
        let alert = NSAlert()
        alert.messageText = "Couldn't check for updates"
        alert.informativeText = "Check your internet connection and try again."
        alert.runModal()
    }
}

private extension String {
    /// Numeric per-component semver compare ("1.2" < "1.10"); non-numeric
    /// trailing parts (e.g. "-beta") are ignored.
    func isNewer(than other: String) -> Bool {
        let a = split(separator: ".").map { Int($0) ?? 0 }
        let b = other.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
