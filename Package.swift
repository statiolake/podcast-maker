// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PodcastMaker",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        .package(url: "https://github.com/awslabs/aws-sdk-swift.git", from: "1.6.2")
    ],
    targets: [
        .binaryTarget(
            name: "whisper",
            path: "third_party/whisper/build-apple/whisper.xcframework"
        ),
        .executableTarget(
            name: "PodcastMaker",
            dependencies: [
                "whisper",
                .product(name: "AWSBedrockRuntime", package: "aws-sdk-swift"),
                .product(name: "AWSSDKIdentity", package: "aws-sdk-swift")
            ],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("AVFoundation")
            ]
        )
    ]
)
