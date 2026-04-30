# Prelude Flutter Session SDK

Flutter plugin that brings Prelude's session-based authentication to
Flutter applications by bridging the native iOS (`PreludeSession`)
and Android (`so.prelude.android:sessions`) session SDKs through a
single Dart API.

> **Status:** `0.1.0` ships the iOS feature surface — email OTP
> login, email and password login, password validation, refresh,
> and logout — through a single Dart API. Android-side bridges to
> `so.prelude.android:sessions` land in a follow-up release; until
> then every Dart method other than `getPlatformVersion` throws
> `MissingPluginException` on Android.

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

## Relationship to `prelude_flutter_sdk`

[`prelude_flutter_sdk`](https://pub.dev/packages/prelude_flutter_sdk)
wraps Prelude's signals and silent-verification surface. This package
wraps the session surface (login, refresh, logout) — apps that only
need silent verification can keep using `prelude_flutter_sdk` alone
and pay no extra binary cost for session code they don't use. Both
packages install side-by-side.

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
└── android/                               # Android plugin (Kotlin, stub)
```

The Dart layer follows the standard three-layer Flutter plugin
pattern ([public API, platform interface, method channel
implementation][plugin-types]) so platform behaviour stays mockable
in tests.

[plugin-types]: https://docs.flutter.dev/packages-and-plugins/developing-packages#types
