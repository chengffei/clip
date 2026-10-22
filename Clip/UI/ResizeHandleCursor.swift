import AppKit

enum ResizeHandleCursor {
    static func frameResizeCursor(for position: FramePosition) -> NSCursor {
        if #available(macOS 15.0, *) {
            return NSCursor.frameResize(position: position.systemPosition, directions: .all)
        } else {
            return position.legacyCursor
        }
    }

    static func setFrameResizeCursor(for position: FramePosition) {
        frameResizeCursor(for: position).set()
    }

    enum FramePosition {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

        @available(macOS 15.0, *)
        var systemPosition: NSCursor.FrameResizePosition {
            switch self {
            case .topLeft: return .topLeft
            case .top: return .top
            case .topRight: return .topRight
            case .right: return .right
            case .bottomRight: return .bottomRight
            case .bottom: return .bottom
            case .bottomLeft: return .bottomLeft
            case .left: return .left
            }
        }

        var legacyCursor: NSCursor {
            switch self {
            case .left, .right:
                return .resizeLeftRight
            case .top, .bottom:
                return .resizeUpDown
            case .topLeft, .topRight, .bottomRight, .bottomLeft:
                return .openHand
            }
        }
    }
}
