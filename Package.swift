// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MDViewer",
    platforms: [.macOS("15.0")],
    dependencies: [
        // Native LaTeX typesetting (CoreText), used for $…$ and $$…$$ math.
        .package(url: "https://github.com/mgriebling/SwiftMath.git", from: "1.7.3")
    ],
    targets: [
        .executableTarget(
            name: "MDViewer",
            dependencies: [.product(name: "SwiftMath", package: "SwiftMath")],
            path: "Sources/MDViewer",
            resources: [
                // mermaid.min.js (MIT) and the page that hosts it; see MermaidView.swift.
                .copy("MermaidAssets")
            ]
        )
    ]
)
