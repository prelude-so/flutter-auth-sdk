// swift-tools-version: 5.9
//
// Manifest for the iOS plugin shell of the Flutter Auth SDK.
// Used by Xcode in Swift-Package-Manager mode; the CocoaPods build
// is configured by `prelude_flutter_auth_sdk.podspec`, which vendors
// the native sources itself. Here they come from apple-auth-sdk,
// which brings apple-sdk (Prelude) transitively.

import PackageDescription

let package = Package(
    name: "prelude_flutter_auth_sdk",
    platforms: [
        .iOS(.v15),
    ],
    products: [
        .library(
            name: "prelude-flutter-auth-sdk",
            targets: ["prelude_flutter_auth_sdk"]
        ),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(url: "https://github.com/prelude-so/apple-auth-sdk", exact: "0.7.0"),
    ],
    targets: [
        .target(
            name: "prelude_flutter_auth_sdk",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "PreludeAuth", package: "apple-auth-sdk"),
                .product(name: "PreludeAuthSocial", package: "apple-auth-sdk"),
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ]
        ),
    ]
)
