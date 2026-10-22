import AppKit
import Foundation

struct AgentWindowsOptions {
    let ownerFilter: String?
    let titleFilter: String?
    let limit: Int?
    let includeSystem: Bool
    let frontmostOnly: Bool
    let metaURL: URL?
    let pretty: Bool

    static func parse(_ arguments: [String]) throws -> AgentWindowsOptions {
        var owner: String?
        var title: String?
        var limit: Int?
        var includeSystem = false
        var frontmostOnly = false
        var meta: String?
        var pretty = false

        var index = 0
        while index < arguments.count {
            let token = arguments[index]

            if token == "--pretty" {
                pretty = true
                index += 1
                continue
            }
            if token == "--frontmost-only" {
                frontmostOnly = true
                index += 1
                continue
            }
            if token == "--all" || token == "--include-system" {
                includeSystem = true
                index += 1
                continue
            }
            if token == "--help" || token == "-h" {
                throw AgentCLIError.help(Self.usageText)
            }

            let key: String
            let value: String

            if let split = token.firstIndex(of: "="), token.hasPrefix("--") {
                key = String(token[..<split])
                value = String(token[token.index(after: split)...])
                index += 1
            } else {
                key = token
                guard index + 1 < arguments.count else {
                    throw AgentCLIError.usage("Missing value for \(token)")
                }
                guard !arguments[index + 1].hasPrefix("--"), arguments[index + 1] != "-h" else {
                    throw AgentCLIError.usage("Missing value for \(token)")
                }
                value = arguments[index + 1]
                index += 2
            }

            switch key {
            case "--owner":
                owner = value
            case "--title":
                title = value
            case "--limit":
                guard let parsed = Int(value), parsed > 0 else {
                    throw AgentCLIError.usage("Invalid limit \(value)")
                }
                limit = parsed
            case "--meta":
                meta = value
            default:
                throw AgentCLIError.usage("Unknown option \(key)")
            }
        }

        return AgentWindowsOptions(
            ownerFilter: owner,
            titleFilter: title,
            limit: limit,
            includeSystem: includeSystem,
            frontmostOnly: frontmostOnly,
            metaURL: meta.map(AgentIO.fileURL(from:)),
            pretty: pretty
        )
    }

    private static let usageText = """
    Usage
      capcap agent windows --pretty
      capcap agent list-windows --owner Safari --limit 5 --pretty

    Options
      --owner             Case-insensitive owner app filter
      --title             Case-insensitive window title filter
      --limit             Maximum windows to return
      --all               Include system surfaces such as menu bar items
      --include-system    Alias for --all
      --frontmost-only    Return only the frontmost app's top normal window
      --meta              Optional metadata JSON file
      --pretty            Pretty print JSON output
    """
}

struct AgentWindowsResult {
    let metadata: [String: Any]
}

enum AgentWindowsLister {
    static func list(options: AgentWindowsOptions) -> AgentWindowsResult {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let frontmostName = NSWorkspace.shared.frontmostApplication?.localizedName

        let windows: [AgentWindowInfo]
        if options.frontmostOnly, let frontmostPID {
            windows = filteredWindows(options: options).filter { $0.ownerPID == frontmostPID && $0.layer == 0 }.prefix(1).map { $0 }
        } else if options.frontmostOnly {
            windows = []
        } else {
            windows = filteredWindows(options: options)
        }

        let limited = options.limit.map { Array(windows.prefix($0)) } ?? windows
        var frontmost: [String: Any] = [:]
        if let frontmostPID {
            frontmost["ownerPID"] = Int(frontmostPID)
        }
        if let frontmostName {
            frontmost["ownerName"] = frontmostName
        }

        let metadata: [String: Any] = [
            "ok": true,
            "command": "agent windows",
            "coordinateSpace": "global-cg",
            "unit": "points",
            "origin": "top-left",
            "includesSystemSurfaces": options.includeSystem,
            "frontmost": frontmost,
            "count": limited.count,
            "windows": limited.map { window in
                var item = window.metadata
                item["index"] = windows.firstIndex { $0.windowID == window.windowID } ?? 0
                item["captureTarget"] = [
                    "target": "window-id",
                    "windowID": Int(window.windowID)
                ]
                item["captureCommand"] = "capcap agent capture --target window-id --window-id \(window.windowID) --out shot.png"
                return item
            }
        ]

        return AgentWindowsResult(metadata: metadata)
    }

    private static func filteredWindows(options: AgentWindowsOptions) -> [AgentWindowInfo] {
        AgentWindowCatalog.visibleWindows().filter { window in
            if !options.includeSystem {
                if window.layer != 0 || window.ownerName == "WindowManager" {
                    return false
                }
            }
            if let owner = options.ownerFilter,
               !window.ownerName.localizedCaseInsensitiveContains(owner) {
                return false
            }
            if let title = options.titleFilter,
               !window.title.localizedCaseInsensitiveContains(title) {
                return false
            }
            return true
        }
    }
}
