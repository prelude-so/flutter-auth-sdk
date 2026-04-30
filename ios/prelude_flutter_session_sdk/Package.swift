// swift-tools-version: 5.9
//
// Manifest for the iOS plugin shell of the Flutter Session SDK.
// Used by Xcode in Swift-Package-Manager mode; the production
// build path is CocoaPods, configured by
// `prelude_flutter_session_sdk.podspec`. The native PreludeSession
// dependency is brought in by the podspec at install time.

import PackageDescription

let package = Package(
    name: "prelude_flutter_session_sdk",
    platforms: [
        .iOS(.v15),
    ],
    products: [
        .library(
            name: "prelude-flutter-session-sdk",
            targets: ["prelude_flutter_session_sdk"]
        ),
    ],
    targets: [
        .target(
            name: "prelude_flutter_session_sdk",
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ]
        ),
    ]
)
