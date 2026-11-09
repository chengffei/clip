import Foundation

/// Plain-text trace at `~/Library/Logs/Clip/clip.log`, in addition to the
/// unified log. Lets both Felix and Claude read what the trigger decided
/// without `log show` privileges or predicates. Keeps the file under ~1 MB.
enum FileLog {
    private static let queue = DispatchQueue(label: "com.chengffei.clip.filelog")
    private static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Clip", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("clip.log")
    }()
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    /// Open for the life of the process; reopening and stat-ing the file per
    /// line cost several syscalls per long-screenshot frame.
    private static var handle: FileHandle?
    private static var writtenSinceSizeCheck = 0
    private static let sizeLimit = 1_000_000

    static func write(_ message: String) {
        let line = "\(stamp.string(from: Date())) \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            rotateIfNeeded(adding: data.count)
            if handle == nil {
                if !FileManager.default.fileExists(atPath: url.path) {
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                }
                handle = try? FileHandle(forWritingTo: url)
                _ = try? handle?.seekToEnd()
            }
            do {
                try handle?.write(contentsOf: data)
            } catch {
                try? handle?.close()
                handle = nil
            }
        }
    }

    /// Every 64 KB of output, check the size; past the cap keep the previous
    /// file as `clip.log.1` instead of deleting it.
    private static func rotateIfNeeded(adding count: Int) {
        writtenSinceSizeCheck += count
        guard writtenSinceSizeCheck > 65_536 || handle == nil else { return }
        writtenSinceSizeCheck = 0
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        guard size > sizeLimit else { return }
        try? handle?.close()
        handle = nil
        let previous = url.deletingLastPathComponent().appendingPathComponent("clip.log.1")
        try? FileManager.default.removeItem(at: previous)
        try? FileManager.default.moveItem(at: url, to: previous)
    }
}
