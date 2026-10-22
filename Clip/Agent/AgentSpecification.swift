import Foundation

/// The executable's discoverable contract also drives unknown-field validation.
enum AgentSpecification {
    static let common = ["type", "color"]
    static let rotation = ["rotation", "rotationDegrees", "rotationRadians"]
    static let fields: [String: [String]] = [
        "rect": ["rect", "lineWidth", "fill", "fillMode", "strokeStyle"] + rotation,
        "ellipse": ["rect", "lineWidth", "fill", "fillMode", "strokeStyle"] + rotation,
        "arrow": ["from", "to", "start", "end", "lineWidth", "style", "control", "controlPoint"],
        "line": ["from", "to", "start", "end", "lineWidth"],
        "text": ["at", "rect", "text", "fontSize", "stroke", "callout", "tip"] + rotation,
        "number": ["center", "number", "tip", "control", "controlPoint"],
        "mosaic": ["rect", "blockSize"],
        "blur": ["rect", "radius", "blockSize"],
        "spotlight": ["rect"],
        "magnifier": ["center", "radius", "zoom", "source", "lineWidth"],
        "pen": ["points", "lineWidth"] + rotation,
        "marker": ["points", "lineWidth"] + rotation
    ]
    static let aliases = ["rectangle": "rect", "box": "rect", "oval": "ellipse", "circle": "ellipse",
                          "label": "text", "numbered": "number", "badge": "number", "pixelate": "mosaic",
                          "loupe": "magnifier", "path": "pen", "highlight": "marker", "highlighter": "marker"]
    static var schema: [String: Any] {
        ["ok": true, "command": "agent schema", "version": 1,
         "commands": ["windows", "displays", "capture", "annotate", "validate", "run", "schema"],
         "coordinateSpace": "pixels", "origin": "top-left",
         "captureCoordinates": "global CG points, top-left of primary display; not image pixels",
         "workflow": ["windows --owner APP --pretty", "capture --window-id ID --out shot.png", "inspect shot.png at its actual pixel dimensions", "validate --input shot.png --spec marks.json", "annotate --input shot.png --spec marks.json --out result.png"],
         "documentFields": ["version", "coordinateSpace", "origin", "imageSize", "annotations", "crop", "beautify"],
         "presentation": ["crop": "Optional [x,y,width,height] in integer input pixels, inside input bounds; applied AFTER annotations",
                          "beautify": "Optional {preset,padding,shadow}; padding is 0...512 pixels (default 64), shadow defaults true; applied AFTER crop",
                          "presets": BeautifyPreset.defaults.filter { !$0.isWallpaper }.map { $0.id }],
         "imageSize": "Optional [pixelWidth, pixelHeight]; rejects specs prepared for a different image size",
         "types": fields.mapValues { common + $0 }, "aliases": aliases,
         "required": ["rect": ["rect"], "ellipse": ["rect"], "arrow": ["from", "to"], "line": ["from", "to"],
                      "text": ["at", "text"], "number": ["center"], "mosaic": ["rect"], "blur": ["rect"], "spotlight": ["rect"], "magnifier": ["center"], "pen": ["points"], "marker": ["points"]],
         "formats": ["point": "[x,y] or {x,y}", "rect": "[x,y,width,height] or {x,y,width,height}; positive size",
                     "color": "#RGB, #RRGGBB, #RRGGBBAA", "lineWidth": "positive tool width; marker/highlighter renders 6 times this width", "fontSize": "positive pixels",
                     "rotation": "degrees; rotationRadians takes precedence", "points": "nonempty array of points"],
         "enums": ["strokeStyle": ["standard", "rounded", "hand-drawn"], "style": ["tapered", "double-ended", "line", "dot-tail"], "fillMode": ["none", "opaque", "translucent"]],
         "notes": ["spotlight regions share one dimming overlay applied after all other annotations", "blur applies Gaussian blur with radius 1...48 pixels (default 12); blockSize is accepted as a fallback radius", "rounded ellipse uses standard stroke", "run captures a new frame; use annotate for an already inspected frame", "validate checks the spec against an image without writing a PNG; inspect rendered output for visual quality"],
         "example": ["version": 1, "coordinateSpace": "pixels", "origin": "top-left", "annotations": [
            ["type": "rect", "rect": [40, 60, 240, 100], "strokeStyle": "rounded", "color": "#007AFF", "lineWidth": 4],
            ["type": "text", "at": [40, 20], "text": "Review this area", "fontSize": 24, "color": "#007AFF"]
         ]]]
    }

    static func validateKeys(_ data: Data) throws {
        let raw: Any
        do { raw = try JSONSerialization.jsonObject(with: data) }
        catch { throw AgentCLIError.failure("Invalid spec JSON: \(error.localizedDescription)") }
        guard let document = raw as? [String: Any] else { throw AgentCLIError.failure("Spec must be a JSON object") }
        try check(document, allowed: ["version", "coordinateSpace", "origin", "imageSize", "annotations", "crop", "beautify"], path: "spec")
        if let beautify = document["beautify"] as? [String: Any] {
            try check(beautify, allowed: ["preset", "padding", "shadow"], path: "beautify")
        }
        guard let annotations = document["annotations"] as? [[String: Any]] else {
            throw AgentCLIError.failure("annotations must be an array of objects")
        }
        for (index, annotation) in annotations.enumerated() {
            let path = "annotations[\(index)]"
            guard let type = annotation["type"] as? String else { throw AgentCLIError.failure("\(path).type is required") }
            let normalized = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "_", with: "-")
            guard let allowed = fields[aliases[normalized] ?? normalized] else {
                throw AgentCLIError.failure("\(path).type: unsupported annotation type \(type)")
            }
            try check(annotation, allowed: common + allowed, path: path)
            for key in ["at", "center", "from", "to", "start", "end", "tip", "control", "controlPoint", "source", "rect"] {
                guard let value = annotation[key] else { continue }
                try checkGeometry(value, rect: key == "rect", path: "\(path).\(key)")
            }
            if let points = annotation["points"] as? [Any] {
                for (i, point) in points.enumerated() { try checkGeometry(point, rect: false, path: "\(path).points[\(i)]") }
            }
        }
    }

    private static func check(_ object: [String: Any], allowed: [String], path: String) throws {
        let unknown = Set(object.keys).subtracting(allowed).sorted()
        guard unknown.isEmpty else { throw AgentCLIError.failure("\(path): unknown fields \(unknown.joined(separator: ", ")); run agent schema") }
    }

    private static func checkGeometry(_ value: Any, rect: Bool, path: String) throws {
        if let array = value as? [Any] {
            guard array.count == (rect ? 4 : 2) else { throw AgentCLIError.failure("\(path): expected \(rect ? 4 : 2) coordinates") }
        } else if let object = value as? [String: Any] {
            try check(object, allowed: rect ? ["x", "y", "width", "height", "w", "h"] : ["x", "y"], path: path)
        }
    }
}
