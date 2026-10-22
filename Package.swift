// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Clip",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Clip", targets: ["Clip"])
    ],
    targets: [
        .target(
            name: "SystemSettingsKit",
            path: "ThirdParty/PermissionFlow/Sources/SystemSettingsKit"
        ),
        .target(
            name: "PermissionFlow",
            dependencies: ["SystemSettingsKit"],
            path: "ThirdParty/PermissionFlow/Sources/PermissionFlow",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "Clip",
            dependencies: [
                "PermissionFlow"
            ],
            path: "Clip",
            exclude: ["App/Info.plist"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AVKit"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Vision"),
                .linkedFramework("VisionKit"),
                .linkedFramework("CoreImage"),
                .linkedFramework("ImageIO"),
                .linkedFramework("QuickLookThumbnailing"),
                .linkedFramework("QuickLookUI"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("Carbon"),
                .linkedFramework("VideoToolbox"),
                .linkedLibrary("z"),
            ]
        ),
        .testTarget(
            name: "ClipTests",
            dependencies: ["Clip"],
            path: "Tests/ClipTests"
        )
    ]
)
