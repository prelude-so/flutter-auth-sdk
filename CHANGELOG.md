# Change Log

Prelude Flutter Session SDK Change Log

## [0.2.0] - 2026-04-30

Adds the Android bridge so the full Dart API now works on Android in
addition to iOS:

- Wires `so.prelude.android:session-sdk:0.1.1` into the Android
  Gradle build.
- Implements `PreludeFlutterSessionSdkPlugin` with per-handle native
  client cache, in-memory step-up challenge cache (the bearer
  challenge token never crosses the channel), and `PreludeSessionError`
  to Flutter error code mapping that mirrors iOS arm-for-arm.
- Minimum Android API: **26**.

## [0.1.0] - 2026-04-30

Initial release of the Prelude Flutter Session SDK. Wraps the native
iOS `PreludeSession` SDK and surfaces its public API through a single
Dart entry point.

iOS feature coverage:

- Email OTP login: `startOTPLogin`, `resendOTP`, `checkOTP`.
- Email and password login: `loginWithPassword`.
- Password validation: `passwordCompliancy`, `validatePassword`.
- Session lifecycle: `refresh`, `logout`, `dispose`.
- Cached session readers: `getProfile`, `getAccessToken`.
- Typed errors for every documented failure case (invalid OTP,
  unauthorized, rate-limited, network, …).

Android: every method-channel call other than `getPlatformVersion`
returns `notImplemented`, surfacing as `MissingPluginException` in
Dart. The native `so.prelude.android:session-sdk` dependency is wired
up alongside the first Android method bridge in a follow-up release.
