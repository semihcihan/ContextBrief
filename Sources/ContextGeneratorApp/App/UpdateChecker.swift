import AppKit

final class UpdateChecker {
    static let shared = UpdateChecker()

    private let repoOwner = "semihcihan"
    private let repoName = "contextbrief"

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private init() {}

    func checkForUpdates(silent: Bool = false) {
#if DEBUG
        return
#endif
        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else {
            return
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else {
                return
            }
            DispatchQueue.main.async {
                if let error {
                    if !silent {
                        self.showError(message: "Could not check for updates.\n\(error.localizedDescription)")
                    }
                    return
                }
                guard
                    let data,
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let tagName = json["tag_name"] as? String,
                    let releaseURL = json["html_url"] as? String
                else {
                    if !silent {
                        self.showError(message: "Could not parse release information.")
                    }
                    return
                }
                let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
                if self.isVersion(latestVersion, newerThan: self.currentVersion) {
                    self.showUpdateAvailable(latestVersion: latestVersion, releaseURL: releaseURL)
                    return
                }
                if !silent {
                    self.showUpToDate()
                }
            }
        }.resume()
    }

    private func isVersion(_ remote: String, newerThan local: String) -> Bool {
        let remoteComponents = remote.split(separator: ".").compactMap { Int($0) }
        let localComponents = local.split(separator: ".").compactMap { Int($0) }
        let count = max(remoteComponents.count, localComponents.count)
        for index in 0..<count {
            let remoteValue = index < remoteComponents.count ? remoteComponents[index] : 0
            let localValue = index < localComponents.count ? localComponents[index] : 0
            if remoteValue > localValue {
                return true
            }
            if remoteValue < localValue {
                return false
            }
        }
        return false
    }

    private func showUpdateAvailable(latestVersion: String, releaseURL: String) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "Context Brief \(latestVersion) is available. You are currently running \(currentVersion)."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        if alert.runModal() != .alertFirstButtonReturn {
            return
        }
        guard let url = URL(string: releaseURL) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func showUpToDate() {
        let alert = NSAlert()
        alert.messageText = "You're Up to Date"
        alert.informativeText = "Context Brief \(currentVersion) is the latest version."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showError(message: String) {
        let alert = NSAlert()
        alert.messageText = "Update Check Failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
