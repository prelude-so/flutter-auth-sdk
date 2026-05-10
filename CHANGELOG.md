# Changelog

Notable changes to the Prelude Flutter Session SDK.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.3.0] - 2026-05-10

### Added
- `listSessions(options)` and `revokeSessions(target)` for managing the user's active sessions, with `PreludeRevokeTarget.all`, `.others`, `.mine`, and `.session(id)`. Revoking the current session also wipes local credentials.
- `sendStepUpOTP(challenge)` — caller-driven OTP delivery for step-up flows.
- `requestStepUp(scope, metadata)` accepts an optional `Map<String, String>` forwarded to the server's step-up audit hook (server caps: 5 keys, 12-char keys, 32-char values).
- `getActiveStepUp()` — read-only accessor for the most recent in-flight challenge so a UI can resume a step-up flow without threading the handle through its state.
- Anti-fraud signals: unauthenticated logins (start OTP, login with password, request step-up) now stamp a `dispatch_id` on the request body when an SDK key is configured. Keys live in the native manifest (`PreludeSDKKey` in `Info.plist`, `<meta-data android:name="so.prelude.sdk_key">` in `AndroidManifest.xml`); an optional `signalsKeyOverride` constructor argument covers runtime-fetched configuration. Absent configuration is a permissive no-op — `dispatch_id` is omitted and the rest of the flow is unchanged.
- New types: `PreludeSessionView`, `PreludeDeviceType`, `PreludeListSessionsOptions`, `PreludeListSessionsResponse`, `PreludeRevokeTarget`.

### Changed
- **Behavior change:** `requestStepUp` and `submitStepUpOTP` no longer auto-fire `POST /otp`. Callers must invoke `sendStepUpOTP(challenge)` explicitly when the next step is an OTP-delivery step.
- Bumps the iOS dependency to `PreludeSession` `0.2.0` and the Android dependency to `so.prelude.android:session-sdk:0.2.0`.

## [0.2.0] - 2026-04-30

### Added
- Android bridge: the full Dart API now works on Android alongside iOS.
- `PreludeFlutterSessionSdkPlugin` (Android) with per-handle native client cache and in-memory step-up challenge cache; the bearer challenge token never crosses the channel.

### Requirements
- Android API 26+
- iOS 15.1+

## [0.1.0] - 2026-04-30

Initial release. iOS-only; the Android bridge was wired up in `0.2.0`.

### Added
- Email OTP login: `startOTPLogin`, `resendOTP`, `checkOTP`.
- Email and password login: `loginWithPassword`.
- Password validation: `passwordCompliancy`, `validatePassword`.
- Session lifecycle: `refresh`, `logout`, `dispose`.
- Cached session readers: `getProfile`, `getAccessToken`.
- Typed errors for every documented failure case (invalid OTP, unauthorized, rate-limited, network, …).
