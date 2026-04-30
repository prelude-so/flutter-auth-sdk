# Prelude Flutter Session SDK

Flutter plugin that brings Prelude's session-based authentication to
Flutter applications by bridging the native iOS (`PreludeSession`)
and Android (`so.prelude.android:session-sdk`) session SDKs through a
single Dart API.

## Installation

Add the package to your Flutter app's `pubspec.yaml`:

```yaml
dependencies:
  prelude_flutter_session_sdk: ^0.2.0
```

Then fetch it:

```bash
flutter pub get
```

Or one line:

```bash
flutter pub add prelude_flutter_session_sdk
```

### iOS

Minimum deployment target: **iOS 15.1**. The plugin's CocoaPods
spec downloads the matching native [`PreludeSession`][native-ios]
sources during `pod install`; if you build with Swift Package
Manager (`flutter config --enable-swift-package-manager`), the
same dependency is resolved through SPM.

[native-ios]: https://github.com/prelude-so/apple-session-sdk

### Android

Minimum SDK: **API 26**. Gradle resolves the matching native
[`so.prelude.android:session-sdk`][native-android] dependency at
build time.

[native-android]: https://github.com/prelude-so/android-session-sdk

## Quick start

```dart
import 'package:prelude_flutter_session_sdk/prelude_flutter_session_sdk.dart';

// Point the client at your project's Prelude session endpoint.
final client = PreludeSessionClient(
  endpoint: Endpoint.custom('https://<your-app>.session.prelude.dev'),
);

// 1) Send a one-time code to the user's email.
await client.startOTPLogin(
  StartOTPLoginOptions(
    identifier: PreludeIdentifier.emailAddress('alice@example.com'),
  ),
);

// 2) Verify the code, get the signed-in user.
final user = await client.checkOTP('123456');
print('userID = ${user.profile.userID}');

// 3) Refresh the access token when needed.
await client.refresh();

// 4) End the session.
await client.logout();
await client.dispose();
```

## Package layout

```
prelude_flutter_session_sdk/
├── lib/
│   ├── prelude_flutter_session_sdk.dart   # public exports
│   └── src/
│       ├── client.dart                    # PreludeSessionClient
│       ├── method_channel.dart
│       ├── platform_interface.dart
│       └── types/                         # value types
├── ios/                                   # iOS plugin (Swift)
└── android/                               # Android plugin (Kotlin)
```

The Dart layer follows the standard three-layer Flutter plugin
pattern ([public API, platform interface, method channel
implementation][plugin-types]) so platform behaviour stays mockable
in tests.

[plugin-types]: https://docs.flutter.dev/packages-and-plugins/developing-packages#types
