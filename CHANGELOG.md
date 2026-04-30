# Change Log

Prelude Flutter Session SDK Change Log

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
Dart. The native `so.prelude.android:sessions` dependency is wired
up alongside the first Android method bridge in a follow-up release.
