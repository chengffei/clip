import AppKit
import CoreGraphics
import Foundation

struct AgentCaptureOptions {
    let target: AgentCaptureTarget
    let outputURL: URL
    let metaURL: URL?
    let pretty: Bool

    static func parse(_ arguments: [String]) throws -> AgentCaptureOptions {
        var targetName: String?
        var output: String?
        var meta: String?
        var pretty = false
        var rect: CGRect?
        var windowID: CGWindowID?
        var screenIndex: Int?
        var displayID: CGDirectDisplayID?

        var index = 0
        while index < arguments.count {
            let token = arguments[index]

            if token == "--pretty" {
                pretty = true
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
            case "--target", "-t":
                targetName = value
            case "--out", "--output", "-o":
                output = value
            case "--meta":
                meta = value
            case "--rect":
                rect = try Self.parseRect(value)
            case "--window-id":
                windowID = try Self.parseWindowID(value)
            case "--screen-index", "--screen":
                guard let parsed = Int(value), parsed >= 0 else {
                    throw AgentCLIError.usage("Invalid screen index \(value)")
                }
                screenIndex = parsed
            case "--display-id":
                displayID = try Self.parseDisplayID(value)
            default:
                throw AgentCLIError.usage("Unknown option \(key)")
            }
        }

        guard let output else { throw AgentCLIError.usage("Missing --out") }
        try AgentIO.validatePaths(inputs: [], outputs: [output] + [meta].compactMap { $0 })
        let target = try AgentCaptureTarget.resolve(
            targetName: targetName,
            rect: rect,
            windowID: windowID,
            screenIndex: screenIndex,
            displayID: displayID
        )

        return AgentCaptureOptions(
            target: target,
            outputURL: AgentIO.fileURL(from: output),
            metaURL: meta.map(AgentIO.fileURL(from:)),
            pretty: pretty
        )
    }

    private static let usageText = """
    Usage
      capcap agent capture --target mouse-screen --out shot.png
      capcap agent capture --target rect --rect 0,0,800,600 --out shot.png
      capcap agent capture --target window-id --window-id 12345 --out shot.png

    Targets
      screen
      mouse-screen
      rect
      window-id
      window-at-cursor
      frontmost-window

    Options
      --target, -t       Capture target
      --out, -o          Output PNG file
      --meta             Optional metadata JSON file
      --rect             Global CG rect as x,y,width,height
      --window-id        WindowServer window ID
      --screen-index     Screen index for screen target
      --display-id       CGDirectDisplayID for screen target
      --pretty           Pretty print JSON output
    """

    static func parseRect(_ value: String) throws -> CGRect {
        let parts = value.split(separator: ",", omittingEmptySubsequences: false).map {
            Double($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard parts.count == 4,
              let x = parts[0],
              let y = parts[1],
              let width = parts[2],
              let height = parts[3],
              x.isFinite,
              y.isFinite,
              width.isFinite,
              height.isFinite,
              width > 0,
              height > 0
        else {
            throw AgentCLIError.usage("Invalid rect \(value)")
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func parseWindowID(_ value: String) throws -> CGWindowID {
        guard let parsed = UInt32(value), parsed > 0 else {
            throw AgentCLIError.usage("Invalid window id \(value)")
        }
        return CGWindowID(parsed)
    }

    static func parseDisplayID(_ value: String) throws -> CGDirectDisplayID {
        guard let parsed = UInt32(value), parsed > 0 else {
            throw AgentCLIError.usage("Invalid display id \(value)")
        }
        return CGDirectDisplayID(parsed)
    }
}

enum AgentCaptureTarget {
    case screen(screenIndex: Int?, displayID: CGDirectDisplayID?)
    case mouseScreen
    case rect(CGRect)
    case windowID(CGWindowID)
    case windowAtCursor
    case frontmostWindow

    static func resolve(
        targetName: String?,
        rect: CGRect?,
        windowID: CGWindowID?,
        screenIndex: Int?,
        displayID: CGDirectDisplayID?
    ) throws -> AgentCaptureTarget {
        let normalized = targetName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")

        let selectorCount = [rect != nil, windowID != nil, screenIndex != nil || displayID != nil].filter { $0 }.count
        guard selectorCount <= 1, !(screenIndex != nil && displayID != nil) else {
            throw AgentCLIError.usage("Capture selectors conflict; choose one rect, window ID, screen index, or display ID")
        }
        if let normalized {
            let allowed: Bool
            if rect != nil { allowed = ["rect", "region"].contains(normalized) }
            else if windowID != nil { allowed = ["window-id", "window"].contains(normalized) }
            else if screenIndex != nil || displayID != nil { allowed = ["screen", "full-screen", "fullscreen"].contains(normalized) }
            else { allowed = true }
            guard allowed else { throw AgentCLIError.usage("Capture selector does not match --target") }
        }

        if normalized == nil {
            if let rect { return .rect(rect) }
            if let windowID { return .windowID(windowID) }
            if screenIndex != nil || displayID != nil { return .screen(screenIndex: screenIndex, displayID: displayID) }
            return .mouseScreen
        }

        switch normalized {
        case "screen", "full-screen", "fullscreen":
            return .screen(screenIndex: screenIndex, displayID: displayID)
        case "mouse-screen", "current-screen", "cursor-screen":
            return .mouseScreen
        case "rect", "region":
            guard let rect else { throw AgentCLIError.usage("Target rect requires --rect") }
            return .rect(rect)
        case "window-id", "window":
            guard let windowID else { throw AgentCLIError.usage("Target window-id requires --window-id") }
            return .windowID(windowID)
        case "window-at-cursor", "cursor-window", "mouse-window":
            return .windowAtCursor
        case "frontmost-window", "front-window", "active-window":
            return .frontmostWindow
        default:
            throw AgentCLIError.usage("Unknown capture target \(targetName ?? "")")
        }
    }
}

struct AgentCaptureResult {
    let metadata: [String: Any]
}

enum AgentCapturer {
    private static let captureTimeout: TimeInterval = 15

    static func capture(options: AgentCaptureOptions) throws -> AgentCaptureResult {
        let payload = try capturePayload(for: options.target)

        guard let pngData = payload.image.pngDataPreservingBacking() else {
            throw AgentCLIError.failure("Could not encode captured PNG")
        }

        try AgentIO.ensureParentDirectory(for: options.outputURL)
        do {
            try pngData.write(to: options.outputURL, options: .atomic)
        } catch {
            throw AgentCLIError.failure("Could not write output \(options.outputURL.path)")
        }

        let cgImage = payload.image.cgImagePreservingBacking()
        let metadata: [String: Any] = [
            "ok": true,
            "command": "agent capture",
            "out": options.outputURL.path,
            "image": [
                "width": cgImage?.width ?? Int(payload.image.size.width.rounded()),
                "height": cgImage?.height ?? Int(payload.image.size.height.rounded())
            ],
            "coordinateSpace": "pixels",
            "origin": "top-left",
            "target": payload.metadata
        ]

        return AgentCaptureResult(metadata: metadata)
    }

    static func capturePayload(for target: AgentCaptureTarget) throws -> AgentCapturePayload {
        switch target {
        case .screen(let screenIndex, let displayID):
            let screen = try AgentScreenCatalog.screen(index: screenIndex, displayID: displayID)
            return try captureScreen(screen, targetType: "screen")

        case .mouseScreen:
            let point = NSEvent.mouseLocation
            let screen = AgentScreenCatalog.screen(containingAppKitPoint: point)
                ?? NSScreen.main
                ?? NSScreen.screens.first
            guard let screen else {
                throw AgentCLIError.failure("No screen is available")
            }
            var payload = try captureScreen(screen, targetType: "mouse-screen")
            payload.metadata["cursorAppKitPoint"] = rectComponentArray(x: point.x, y: point.y)
            return payload

        case .rect(let rect):
            return try captureRect(rect)

        case .windowID(let id):
            let info = AgentWindowCatalog.visibleWindows().first { $0.windowID == id }
            return try captureWindow(id: id, info: info, targetType: "window-id")

        case .windowAtCursor:
            let point = NSEvent.mouseLocation
            let cgPoint = AgentScreenCatalog.cgPoint(fromAppKitPoint: point)
            guard let info = AgentWindowCatalog.window(at: cgPoint) else {
                throw AgentCLIError.failure("No window found at cursor")
            }
            return try captureWindow(id: info.windowID, info: info, targetType: "window-at-cursor")

        case .frontmostWindow:
            guard let app = NSWorkspace.shared.frontmostApplication else {
                throw AgentCLIError.failure("No frontmost application is available")
            }
            guard let info = AgentWindowCatalog.frontmostWindow(forPID: app.processIdentifier) else {
                throw AgentCLIError.failure("No frontmost window found for \(app.localizedName ?? "frontmost application")")
            }
            return try captureWindow(id: info.windowID, info: info, targetType: "frontmost-window")
        }
    }

    private static func captureScreen(_ screen: NSScreen, targetType: String) throws -> AgentCapturePayload {
        guard let displayID = AgentScreenCatalog.displayID(for: screen) else {
            throw AgentCLIError.failure("Could not resolve display id")
        }
        let rect = CGDisplayBounds(displayID)
        guard let image = ScreenCapturer.capture(
            rect: rect,
            screen: screen,
            timeout: captureTimeout
        ) else {
            throw AgentCLIError.failure(
                "Screen capture failed; make sure the screen is unlocked and Screen Recording permission is granted"
            )
        }

        return AgentCapturePayload(
            image: image,
            metadata: [
                "type": targetType,
                "displayID": Int(displayID),
                "screenIndex": AgentScreenCatalog.index(of: screen) ?? NSNull(),
                "scale": Double(screen.backingScaleFactor),
                "rect": rectJSON(rect)
            ]
        )
    }

    private static func captureRect(_ rect: CGRect) throws -> AgentCapturePayload {
        guard let screen = AgentScreenCatalog.screen(containingCGRect: rect),
              let displayID = AgentScreenCatalog.displayID(for: screen)
        else {
            throw AgentCLIError.failure("Rect must fit inside one display")
        }

        guard let image = ScreenCapturer.capture(
            rect: rect,
            screen: screen,
            timeout: captureTimeout
        ) else {
            throw AgentCLIError.failure(
                "Rect capture failed; make sure the screen is unlocked and Screen Recording permission is granted"
            )
        }

        return AgentCapturePayload(
            image: image,
            metadata: [
                "type": "rect",
                "displayID": Int(displayID),
                "screenIndex": AgentScreenCatalog.index(of: screen) ?? NSNull(),
                "scale": Double(screen.backingScaleFactor),
                "rect": rectJSON(rect)
            ]
        )
    }

    private static func captureWindow(
        id: CGWindowID,
        info: AgentWindowInfo?,
        targetType: String
    ) throws -> AgentCapturePayload {
        if let info, info.usesCompositedScreenBackdrop {
            let payload = try captureRect(info.frame)
            var metadata = payload.metadata
            metadata["type"] = targetType
            metadata["windowID"] = Int(id)
            metadata["window"] = info.metadata
            metadata["captureMode"] = "composited-rect"
            return AgentCapturePayload(image: payload.image, metadata: metadata)
        }

        let pointSize = info.map { NSSize(width: $0.frame.width, height: $0.frame.height) }
        guard let image = ScreenCapturer.capture(
            windowID: id,
            pointSize: pointSize,
            timeout: captureTimeout
        ),
              !ScreenCapturer.isEffectivelyTransparent(image)
        else {
            throw AgentCLIError.failure(
                "Window capture failed; make sure the screen is unlocked and Screen Recording permission is granted"
            )
        }

        var metadata: [String: Any] = [
            "type": targetType,
            "windowID": Int(id),
            "captureMode": "window"
        ]
        if let info {
            metadata["window"] = info.metadata
        }

        return AgentCapturePayload(image: image, metadata: metadata)
    }

    private static func rectJSON(_ rect: CGRect) -> [Double] {
        [
            Double(rect.origin.x),
            Double(rect.origin.y),
            Double(rect.width),
            Double(rect.height)
        ]
    }

    private static func rectComponentArray(x: CGFloat, y: CGFloat) -> [Double] {
        [Double(x), Double(y)]
    }
}

struct AgentCapturePayload {
    let image: NSImage
    var metadata: [String: Any]
}

struct AgentWindowInfo {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let title: String
    let layer: Int
    let frame: CGRect

    var usesCompositedScreenBackdrop: Bool {
        // Screen-saver-level editors/overlays must be isolated from other apps.
        // Only menu-level system surfaces need the composited backdrop fallback.
        layer >= 20 && layer < Int(CGWindowLevelForKey(.screenSaverWindow))
    }

    var metadata: [String: Any] {
        [
            "windowID": Int(windowID),
            "ownerPID": Int(ownerPID),
            "ownerName": ownerName,
            "title": title,
            "layer": layer,
            "usesCompositedScreenBackdrop": usesCompositedScreenBackdrop,
            "frame": [
                Double(frame.origin.x),
                Double(frame.origin.y),
                Double(frame.width),
                Double(frame.height)
            ]
        ]
    }
}

enum AgentWindowCatalog {
    static func visibleWindows() -> [AgentWindowInfo] {
        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier

        return infoList.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsNS = info[kCGWindowBounds as String] as? NSDictionary,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer >= 0
            else { return nil }

            if pid == ownPID && layer >= Int(CGWindowLevelForKey(.screenSaverWindow)) {
                return nil
            }

            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha <= 0 {
                return nil
            }

            var rect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsNS as CFDictionary, &rect) else {
                return nil
            }
            guard rect.width > 1, rect.height > 1 else { return nil }

            let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""
            let title = info[kCGWindowName as String] as? String ?? ""
            let windowID = info[kCGWindowNumber as String] as? CGWindowID ?? 0
            guard windowID > 0 else { return nil }

            return AgentWindowInfo(
                windowID: windowID,
                ownerPID: pid,
                ownerName: ownerName,
                title: title,
                layer: layer,
                frame: rect
            )
        }
    }

    static func window(at cgPoint: CGPoint) -> AgentWindowInfo? {
        visibleWindows().first { $0.frame.contains(cgPoint) }
    }

    static func frontmostWindow(forPID pid: pid_t) -> AgentWindowInfo? {
        visibleWindows().first { info in
            info.ownerPID == pid && info.layer == 0
        }
    }
}

enum AgentScreenCatalog {
    static var metadata: [String: Any] {
        ["ok": true, "command": "agent displays", "coordinateSpace": "global-cg", "unit": "points", "origin": "top-left",
         "screenRecordingPermission": CGPreflightScreenCaptureAccess(),
         "displays": NSScreen.screens.enumerated().compactMap { index, screen -> [String: Any]? in
             guard let id = displayID(for: screen) else { return nil }
             let rect = CGDisplayBounds(id)
             return ["screenIndex": index, "displayID": Int(id), "name": screen.localizedName,
                     "scale": Double(screen.backingScaleFactor), "rect": [rect.minX, rect.minY, rect.width, rect.height]]
         }]
    }

    static func screen(index: Int?, displayID: CGDirectDisplayID?) throws -> NSScreen {
        if let displayID {
            guard let screen = NSScreen.screens.first(where: { self.displayID(for: $0) == displayID }) else {
                throw AgentCLIError.failure("No screen found for display id \(displayID)")
            }
            return screen
        }

        if let index {
            guard NSScreen.screens.indices.contains(index) else {
                throw AgentCLIError.failure("No screen found at index \(index)")
            }
            return NSScreen.screens[index]
        }

        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            throw AgentCLIError.failure("No screen is available")
        }
        return screen
    }

    static func screen(containingAppKitPoint point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    static func screen(containingCGRect rect: CGRect) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let displayID = displayID(for: screen) else { return false }
            return CGDisplayBounds(displayID).contains(rect)
        }
    }

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    static func index(of screen: NSScreen) -> Int? {
        NSScreen.screens.firstIndex { $0 === screen }
    }

    static func cgPoint(fromAppKitPoint point: NSPoint) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: point.x, y: primaryHeight - point.y)
    }
}
