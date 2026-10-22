import Foundation
import CryptoKit

/// Downloads a capcap release zip and installs it in place of the running app.
///
/// The running `.app` bundle can't overwrite itself while it's open, so the
/// final swap is handed to a detached `/bin/bash` helper: it waits for this
/// process to exit, replaces the bundle, and relaunches. The caller must
/// terminate the app immediately after `install` returns.
final class UpdateInstaller: NSObject {
    static let shared = UpdateInstaller()

    enum InstallError: Error {
        case download
        case checksumMismatch
        case unzipFailed
        case bundleNotFound
        case notWritable
    }

    private var session: URLSession?
    private var progressHandler: ((Double) -> Void)?
    private var finishHandler: ((Result<URL, Error>) -> Void)?

    // MARK: - Download

    /// Downloads `url` to a temp file, reporting progress as a 0...1 fraction.
    /// Both handlers fire on the main thread; `completion` yields the path of
    /// the downloaded zip on success.
    func downloadZip(
        from url: URL,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        progressHandler = progress
        finishHandler = completion

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 300
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session

        var request = URLRequest(url: url)
        request.setValue("capcap", forHTTPHeaderField: "User-Agent")
        session.downloadTask(with: request).resume()
    }

    private func deliver(_ result: Result<URL, Error>) {
        let handler = finishHandler
        finishHandler = nil
        progressHandler = nil
        DispatchQueue.main.async { handler?(result) }
    }

    // MARK: - Install

    /// Verifies the checksum (when `expectedSHA256` is given), unzips the
    /// release, and spawns the detached helper that swaps the bundle and
    /// relaunches. Throws before spawning the helper if anything looks wrong,
    /// so a failure always leaves the running app untouched.
    ///
    /// `phase` is invoked synchronously on this thread as each step begins, so
    /// the UI can show "verifying / extracting / installing" in turn.
    static func install(zipAt zipURL: URL,
                         expectedSHA256: String?,
                         phase: (InstallPhase) -> Void) throws {
        let fm = FileManager.default
        // The downloaded zip is always disposable. The unpacked scratch dir is
        // disposable too, *unless* the detached helper took ownership of it —
        // it reads the new bundle from there after this process exits. So any
        // failure before the hand-off cleans the scratch dir up here; a
        // successful hand-off leaves it for the helper, which deletes it last.
        var scratchDir: URL?
        var handedOff = false
        defer {
            try? fm.removeItem(at: zipURL)
            if let dir = scratchDir, !handedOff { try? fm.removeItem(at: dir) }
        }

        // 1. Checksum — guards against a truncated or corrupted download.
        phase(.verifying)
        if let expected = expectedSHA256 {
            let data = try Data(contentsOf: zipURL)
            let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard hex == expected.lowercased() else { throw InstallError.checksumMismatch }
        }

        // 2. Unzip into a scratch directory.
        phase(.unzipping)
        let workDir = fm.temporaryDirectory
            .appendingPathComponent("capcap-update-\(UUID().uuidString)", isDirectory: true)
        scratchDir = workDir
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        try runProcess("/usr/bin/ditto", ["-x", "-k", zipURL.path, workDir.path],
                       throwing: .unzipFailed)

        // 3. Locate the unpacked .app and sanity-check it has an executable.
        phase(.installing)
        let entries = (try? fm.contentsOfDirectory(atPath: workDir.path)) ?? []
        guard let appName = entries.first(where: { $0.hasSuffix(".app") }) else {
            throw InstallError.bundleNotFound
        }
        let newApp = workDir.appendingPathComponent(appName)
        guard fm.fileExists(atPath: newApp.appendingPathComponent("Contents/MacOS").path) else {
            throw InstallError.bundleNotFound
        }
        // Strip quarantine so Gatekeeper doesn't block the relaunch.
        _ = try? runProcess("/usr/bin/xattr",
                            ["-dr", "com.apple.quarantine", newApp.path],
                            throwing: .unzipFailed)

        // 4. Confirm we can actually replace the running bundle.
        let oldApp = Bundle.main.bundleURL
        let parent = oldApp.deletingLastPathComponent()
        guard fm.isWritableFile(atPath: parent.path) else { throw InstallError.notWritable }

        // 5. Hand the swap off to a detached helper and let the caller quit.
        spawnSwapHelper(newApp: newApp.path, oldApp: oldApp.path)
        handedOff = true
    }

    /// Deletes leftover update artifacts (`capcap-update-*` zips and scratch
    /// dirs) from the temp directory. The current run cleans up after itself,
    /// but a crash or force-quit between download and swap can strand files;
    /// calling this before each update keeps them from accumulating.
    static func cleanStaleArtifacts() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: fm.temporaryDirectory,
            includingPropertiesForKeys: nil
        ) else { return }
        for url in entries where url.lastPathComponent.hasPrefix("capcap-update-") {
            try? fm.removeItem(at: url)
        }
    }

    private static func runProcess(
        _ launchPath: String,
        _ arguments: [String],
        throwing error: InstallError
    ) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = arguments
        task.standardOutput = nil
        task.standardError = nil
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { throw error }
    }

    /// Launches a `/bin/bash` script that outlives this process: it waits for
    /// capcap to quit, swaps the bundle (keeping a backup it restores on
    /// failure), and reopens the app.
    private static func spawnSwapHelper(newApp: String, oldApp: String) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        NEW="$1"; OLD="$2"; PID="$3"
        # Wait (up to ~15s) for capcap to exit before touching its bundle.
        for _ in $(seq 1 150); do
          kill -0 "$PID" 2>/dev/null || break
          sleep 0.1
        done
        BACKUP="${OLD}.capcap-backup-${PID}"
        mv "$OLD" "$BACKUP" || exit 1
        if /usr/bin/ditto "$NEW" "$OLD"; then
          /usr/bin/xattr -dr com.apple.quarantine "$OLD" 2>/dev/null || true
          rm -rf "$BACKUP"
        else
          # Restore the old bundle so the user isn't left with nothing.
          rm -rf "$OLD"
          mv "$BACKUP" "$OLD"
        fi
        rm -rf "$(dirname "$NEW")"
        /usr/bin/open "$OLD"
        """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", script, "capcap-updater", newApp, oldApp, String(pid)]
        try? task.run()
    }
}

extension UpdateInstaller: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let clamped = min(max(fraction, 0), 1)
        DispatchQueue.main.async { self.progressHandler?(clamped) }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // A non-200 response still "finishes" — its body is an error page, not
        // a zip — so reject it before the caller tries to unzip.
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            deliver(.failure(InstallError.download))
            return
        }
        // URLSession deletes `location` once this delegate returns, so move the
        // file out to a stable path first.
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("capcap-update-\(UUID().uuidString).zip")
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            deliver(.success(dest))
        } catch {
            deliver(.failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        // Success is already reported from didFinishDownloadingTo; this only
        // catches transport failures (and deliver() ignores a second call).
        if let error = error { deliver(.failure(error)) }
        self.session?.finishTasksAndInvalidate()
        self.session = nil
    }
}
