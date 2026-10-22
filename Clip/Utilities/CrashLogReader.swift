import Foundation

/// Locates and reads the most recent macOS crash report for capcap.
enum CrashLogReader {
    /// A log file on disk — its URL plus when it was written.
    struct Entry {
        let url: URL
        let date: Date
    }

    /// macOS names crash reports "<process>-<timestamp>.<ext>"; the process
    /// name matches capcap's CFBundleExecutable.
    private static let processName = "capcap"

    /// Returns the newest macOS crash report belonging to capcap, or nil if no
    /// report exists. This only stats the files and does not read their contents.
    static func latestLogFile() -> Entry? {
        latestCrashFile()
    }

    /// Scans the standard DiagnosticReports directories and returns the newest
    /// crash report belonging to capcap, or nil if the app has never crashed.
    /// This only stats the directory — it does not read any file contents.
    private static func latestCrashFile() -> Entry? {
        var newest: Entry?
        for dir in diagnosticReportDirs() {
            guard let entries = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for url in entries {
                guard isCapcapCrashReport(url) else { continue }
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                if newest == nil || date > newest!.date {
                    newest = Entry(url: url, date: date)
                }
            }
        }
        return newest
    }

    /// Deletes capcap-owned macOS crash reports from the user's
    /// DiagnosticReports folders.
    static func deleteAllLogs() {
        for dir in diagnosticReportDirs() {
            guard let entries = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in entries where isCapcapCrashReport(url) {
                try? fm.removeItem(at: url)
            }
        }
    }

    /// Reads a log file and returns a human-readable rendering. Modern `.ips`
    /// reports are a one-line JSON header followed by a JSON body; both are
    /// pretty-printed when possible, falling back to the raw text.
    static func readableText(at url: URL) -> String {
        let raw: String
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            raw = utf8
        } else if let data = try? Data(contentsOf: url) {
            raw = String(decoding: data, as: UTF8.self)
        } else {
            return ""
        }

        guard url.pathExtension.lowercased() == "ips",
              let newline = raw.firstIndex(of: "\n") else {
            return raw
        }
        let header = String(raw[..<newline])
        let body = String(raw[raw.index(after: newline)...])
        guard let prettyHeader = prettyJSON(header),
              let prettyBody = prettyJSON(body) else {
            return raw
        }
        return prettyHeader + "\n\n" + prettyBody
    }

    private static func prettyJSON(_ string: String) -> String? {
        guard let data = string.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ) else {
            return nil
        }
        return String(decoding: pretty, as: UTF8.self)
    }

    private static let fm = FileManager.default

    private static func diagnosticReportDirs() -> [URL] {
        guard let library = fm.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return []
        }
        return [
            library.appendingPathComponent("Logs/DiagnosticReports", isDirectory: true),
            library.appendingPathComponent("Logs/DiagnosticReports/Retired", isDirectory: true),
        ]
    }

    private static func isCapcapCrashReport(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard ext == "ips" || ext == "crash" else { return false }
        return url.lastPathComponent.hasPrefix(processName + "-")
    }
}
