// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TailOpsMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TailOpsCore", targets: ["TailOpsCore"]),
        .library(name: "TailOpsIntents", targets: ["TailOpsIntents"]),
        .library(name: "TailOpsShared", targets: ["TailOpsShared"]),
        .library(name: "TailOpsMacViews", targets: ["TailOpsMacViews"]),
        .library(name: "TailOpsWidgetViews", targets: ["TailOpsWidgetViews"]),
        .executable(name: "TailOpsCoreValidation", targets: ["TailOpsCoreValidation"])
    ],
    targets: [
        .target(name: "TailOpsCore"),
        .target(
            name: "TailOpsShared",
            dependencies: ["TailOpsCore"],
            path: "Shared",
            sources: [
                "PingSparklineView.swift",
                "PreviewFixtures.swift",
                "SharedSnapshotStore.swift"
            ]
        ),
        .target(
            name: "TailOpsIntents",
            dependencies: ["TailOpsCore", "TailOpsShared"],
            path: "Intents",
            sources: [
                "TailOpsWidgetIntents.swift"
            ]
        ),
        .target(
            name: "TailOpsMacViews",
            dependencies: ["TailOpsCore", "TailOpsShared"],
            path: "App",
            exclude: ["TailOpsMacApp.swift"],
            sources: [
                "DesignPreviewGallery.swift",
                "TaildropServiceProvider.swift",
                "TailscaleStatusProvider.swift",
                "TailOpsActionSettingsModel.swift",
                "TailOpsConstellationIcon.swift",
                "TailOpsPreferencesModel.swift",
                "TailOpsSettingsView.swift",
                "TailOpsMenuView.swift",
                "TailnetMonitor.swift"
            ]
        ),
        .target(
            name: "TailOpsWidgetViews",
            dependencies: ["TailOpsCore", "TailOpsIntents", "TailOpsShared"],
            path: "Widget",
            exclude: ["TailOpsWidgetBundle.swift"],
            sources: [
                "TailOpsWidget.swift"
            ]
        ),
        .executableTarget(name: "TailOpsCoreValidation", dependencies: ["TailOpsCore", "TailOpsShared"])
    ]
)
