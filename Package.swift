// swift-tools-version:5.9
// TapeCore: the platform-independent half of Tape (data client, credit governor,
// series parsing, poll schedule, symbol search, formatting). Foundation only, so it
// builds and tests on macOS and Linux as well as iOS.
import PackageDescription

let package = Package(
    name: "TapeCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TapeCore", targets: ["TapeCore"])
    ],
    targets: [
        .target(name: "TapeCore", path: "Sources/TapeCore"),
        .testTarget(name: "TapeCoreTests", dependencies: ["TapeCore"], path: "Tests/TapeCoreTests")
    ]
)
