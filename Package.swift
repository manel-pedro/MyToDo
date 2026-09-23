// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SevenDayTodo",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SevenDayTodo", targets: ["SevenDayTodo"])
    ],
    targets: [
        .executableTarget(
            name: "SevenDayTodo",
            path: "Sources/SevenDayTodo"
        )
    ]
)

