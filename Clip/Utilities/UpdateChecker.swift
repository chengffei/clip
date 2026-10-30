import AppKit

/// Manual update check. This is the only place Clip goes online, and only when
/// the user picks "Check for Updates…". Two sources are asked at once and the
/// first answer wins, because github.com alone is slow or unreachable on some
/// networks:
/// - a HEAD request to the GitHub releases page, which redirects to the latest
///   tag (the REST API is avoided: 60 anonymous requests an hour per IP, which
///   shared networks run out of);
/// - jsDelivr's resolver for the repository's latest version tag.
enum UpdateChecker {
    struct Release: Equatable {
        let version: String
        let pageURL: URL
    }

    static let releasesPage = URL(string: "https://github.com/chengffei/clip/releases/latest")!
    static let jsDelivrResolver = URL(string: "https://data.jsdelivr.com/v1/packages/gh/chengffei/clip/resolved")!

    private static let timeout: TimeInterval = 12
    /// When the first answer says "up to date", how long to wait for the other
    /// source in case it already knows a newer release (CDN caches can lag).
    private static let graceForSecondAnswer: TimeInterval = 1.5

    private static var isChecking = false

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Main-thread bookkeeping for one check.
    private final class Round {
        let expected: Int
        var versions: [String] = []
        var errors: [Error] = []
        var done = false
        init(expected: Int) { self.expected = expected }
        var newest: String? { versions.max { isNewer($1, than: $0) } }
    }

    /// Finds the latest release and reports the outcome in an alert.
    static func checkInteractively() {
        guard !isChecking else { return }
        isChecking = true
        ToastWindow.show(message: L10n.updateChecking, duration: timeout + 3)

        let round = Round(expected: 2)
        let finish: (Result<Release, Error>) -> Void = { result in
            guard !round.done else { return }
            round.done = true
            isChecking = false
            ToastWindow.dismiss()
            present(result)
        }
        let deliver: (String, Result<String, Error>, Date) -> Void = { source, result, started in
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            switch result {
            case .success(let version):
                FileLog.write("update check \(source) \(version) in \(ms)ms")
                round.versions.append(version)
            case .failure(let error):
                FileLog.write("update check \(source) failed in \(ms)ms: \(error.localizedDescription)")
                round.errors.append(error)
            }
            if let newest = round.newest, isNewer(newest, than: currentVersion) {
                finish(.success(release(for: newest)))
            } else if round.versions.count + round.errors.count == round.expected {
                if let newest = round.newest {
                    finish(.success(release(for: newest)))
                } else {
                    finish(.failure(round.errors.first ?? URLError(.badServerResponse)))
                }
            } else if round.versions.count == 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + graceForSecondAnswer) {
                    if let newest = round.newest { finish(.success(release(for: newest))) }
                }
            }
        }

        let started = Date()
        var head = URLRequest(url: releasesPage, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        head.httpMethod = "HEAD"
        URLSession.shared.dataTask(with: head) { _, response, error in
            let result: Result<String, Error>
            if let error {
                result = .failure(error)
            } else if let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let url = http.url, let release = release(fromTagURL: url) {
                result = .success(release.version)
            } else {
                result = .failure(URLError(.badServerResponse))
            }
            DispatchQueue.main.async { deliver("github", result, started) }
        }.resume()

        let cdn = URLRequest(url: jsDelivrResolver, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        URLSession.shared.dataTask(with: cdn) { data, response, error in
            let result: Result<String, Error>
            if let error {
                result = .failure(error)
            } else if (response as? HTTPURLResponse)?.statusCode == 200, let data,
                      let version = version(fromJSDelivr: data) {
                result = .success(version)
            } else {
                result = .failure(URLError(.badServerResponse))
            }
            DispatchQueue.main.async { deliver("jsdelivr", result, started) }
        }.resume()
    }

    static func release(for version: String) -> Release {
        Release(version: version, pageURL: URL(string: "https://github.com/chengffei/clip/releases/tag/v\(version)") ?? releasesPage)
    }

    /// Reads `{"version": "0.5.0", …}` from jsDelivr's resolver.
    static func version(fromJSDelivr data: Data) -> String? {
        struct Payload: Decodable { let version: String? }
        guard let version = (try? JSONDecoder().decode(Payload.self, from: data))?.version,
              version.first?.isNumber == true else { return nil }
        return version
    }

    /// Reads the version from a release page URL such as
    /// `https://github.com/chengffei/clip/releases/tag/v0.5.0`.
    static func release(fromTagURL url: URL) -> Release? {
        let parts = url.pathComponents
        guard parts.count >= 2, parts[parts.count - 2] == "tag" else { return nil }
        let tag = parts[parts.count - 1]
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard version.first?.isNumber == true else { return nil }
        return Release(version: version, pageURL: url)
    }

    /// Compares dotted numeric versions, so "0.10.0" is newer than "0.9.1".
    static func isNewer(_ remote: String, than local: String) -> Bool {
        let parts = { (v: String) in v.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 } }
        let r = parts(remote), l = parts(local)
        for i in 0..<max(r.count, l.count) {
            let a = i < r.count ? r[i] : 0, b = i < l.count ? l[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func present(_ result: Result<Release, Error>) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        let current = currentVersion
        switch result {
        case .success(let release) where isNewer(release.version, than: current):
            alert.messageText = L10n.updateAvailableTitle(release.version)
            alert.informativeText = L10n.updateAvailableMessage(current)
            alert.addButton(withTitle: L10n.updateDownload)
            alert.addButton(withTitle: L10n.updateLater)
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(release.pageURL)
            }
        case .success:
            alert.messageText = L10n.updateUpToDateTitle
            alert.informativeText = L10n.updateUpToDateMessage(current)
            alert.runModal()
        case .failure(let error):
            alert.alertStyle = .warning
            alert.messageText = L10n.updateFailedTitle
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: L10n.updateOpenReleasesPage)
            alert.addButton(withTitle: L10n.updateLater)
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(releasesPage)
            }
        }
    }
}
