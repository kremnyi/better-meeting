// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BetterMeetingMac",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "BetterMeeting", targets: ["BetterMeetingApp"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/argmaxinc/argmax-oss-swift.git",
            from: "1.0.0"
        ),
    ],
    targets: [
        .executableTarget(
            name: "BetterMeetingApp",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ],
            path: "Sources/BetterMeetingApp"
        ),
    ],
    swiftLanguageModes: [.v5]
)
