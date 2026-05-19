// swift-tools-version: 5.9
//
// Manifest for the iOS plugin shell of the Flutter Auth SDK.
// Used by Xcode in Swift-Package-Manager mode; the production
// build path is CocoaPods, configured by
// `prelude_flutter_auth_sdk.podspec`. The native PreludeAuth
// dependency is brought in by the podspec at install time.

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
    targets: [
        .target(
            name: "prelude_flutter_auth_sdk",
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ]
        ),
    ]
)
