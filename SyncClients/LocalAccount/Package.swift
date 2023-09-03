// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LocalAccount",
	platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "LocalAccount",
            targets: ["LocalAccount"]),
    ],
	dependencies: [
		.package(url: "https://github.com/Ranchero-Software/RSParser.git", .upToNextMajor(from: "2.0.2")),
		.package(url: "https://github.com/Ranchero-Software/RSWeb.git", .upToNextMajor(from: "1.0.0")),
	],
    targets: [
		// Targets are the basic building blocks of a package. A target can define a module or a test suite.
		// Targets can depend on other targets in this package, and on products in packages this package depends on.
		.target(
			name: "LocalAccount",
			dependencies: [
				"RSParser",
				"RSWeb"]
		),
		.testTarget(
			name: "LocalAccountTests",
			dependencies: ["LocalAccount"]),
	]
)
