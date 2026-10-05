# Changelog

Notable changes to the Prelude Flutter Auth SDK.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.7.0] - 2026-09-25

### Added
- Passkey login: `loginWithPasskey([PasskeyLoginOptions])` signs a user in with the platform authenticator — no password, no OTP. `PasskeyLoginOptions.autofill` offers credentials through the keyboard's AutoFill row on iOS.
- Passkey registration: `registerPasskey(RegisterPasskeyOptions)` for a session holding `prld:passkey:write`, returning a `PasskeyRegistrationResult` whose `alreadyRegistered` flag marks an idempotent repeat.
- Passkey management: `listPasskeys()`, `renamePasskey(credentialID, nickname)` and `deletePasskey(credentialID)`, returning `PreludePasskeyCredential` values.
- `continueStepUpWithPasskey(StepUpChallenge)` advances a step-up whose `currentStep` is `verify_passkey`, with the same next-challenge-or-`null` contract as `submitStepUpOTP`.
- `PasskeyNotSupportedException` (`passkey_not_supported`) and `PasskeyAlreadyRegisteredException` (`passkey_already_registered`, reported by Android; iOS surfaces a generic registration failure until the native SDK distinguishes it). `PasskeyNotConfiguredException`, `PasskeyRegistrationFailedException`, `PasskeyStepUnavailableException` and `PasswordNotSetException` were already mapped by the bridge but not exported from the library — they are now.
- `NoLoginConfigException` (`no_login_config`), returned when starting an OTP login
  while the app has no login configuration accepting the
  identifier's channel. Create one via the Auth Management API.

### Changed
- Bumps the iOS dependency to `PreludeAuth` `0.7.0` and the Android dependency to `so.prelude.android:auth-sdk:0.7.1`, the native releases that add passkey support. On Android, a deactivated user's login now maps to a forbidden error instead of a generic one.
- The Android plugin is now `ActivityAware`: passkey ceremonies present a system sheet, which the application context can't launch. Calls made while the engine is attached to no Activity throw `InvalidConfigurationException`.
- Passkey integrators on Android add `androidx.credentials` themselves (plus `credentials-play-services-auth` below API 34); the native SDK ships it `compileOnly` so apps that skip passkeys pull no extra dependency.

## [0.6.0] - 2026-07-01

### Added
- Social login. `loginWithOAuth(OAuthLoginOptions)` presents the provider page in a system web session and establishes a session; `initiateOAuthLogin` / `finalizeOAuthLogin` back it for apps that present the page themselves. Unverified provider emails surface as `OAuthOtpRequired`. New types: `OAuthProvider`, `OAuthLoginOptions`, `InitiateOAuthLoginOptions`, `FinalizeOAuthLoginResult` (`OAuthLoggedIn` / `OAuthOtpRequired`), and `CancelledException` for a dismissed page.
- `checkOAuthEmailOTP(OAuthEmailChallenge, String)` completes an OAuth login when the provider's email must be verified (e.g. Microsoft). `OAuthOtpRequired` now carries an `OAuthEmailChallenge` handle; redeem it with the code the user receives. The verification token stays in the native plugin's per-handle cache, so concurrent logins stay isolated and the bearer credential never crosses the channel.
- On Android, social login opens a Chrome Custom Tab: apps add `androidx.browser` and declare `OAuthRedirectActivity` with their redirect scheme. On iOS no extra config is needed.

### Changed
- Bumps the iOS dependency to `PreludeAuth` `0.6.0` and the Android dependency to `so.prelude.android:auth-sdk:0.6.0`, the native releases that add social login and OAuth email-link completion.

## [0.5.0] - 2026-06-12

### Added
- `migrate(MigrateOptions)` — exchange a legacy bearer token for a Prelude session via PKCE-bound `/migration` ⇒ `/login/finalize`. Idempotent (a cached session short-circuits) and single-flight (concurrent callers share one exchange), so the legacy token is spent at most once. The token is wrapped in a `RedactedString` so the options object never leaks it through `toString`.
- `canChangePassword()` — returns `true` when the current session already carries `prld:pwd:write`, so a UI can skip step-up before `changePassword`.

### Changed
- Bumps the iOS dependency to `PreludeAuth` `0.4.0` and the Android dependency to `so.prelude.android:auth-sdk:0.5.0`. The native `0.4.0` release also brings per-domain DPoP clock-skew correction, best-effort (non-blocking) signals dispatch, and race-safe cached-session accessors.

## [0.4.0] - 2026-05-18

First release under the new package name. Continues the history of
[`prelude_flutter_session_sdk`](https://pub.dev/packages/prelude_flutter_session_sdk);
versions ≤ `0.3.0` below are listed for migration context.

### Changed
- **Renamed**: package `prelude_flutter_session_sdk` → `prelude_flutter_auth_sdk`; `PreludeSessionClient` → `PreludeAuthClient`; `PreludeSessionException` → `PreludeAuthException`. Native dependencies follow: `PreludeAuth` on iOS and `so.prelude.android:auth-sdk` on Android.
- Bumps the iOS dependency to `PreludeAuth` `0.3.0` and the Android dependency to `so.prelude.android:auth-sdk:0.3.0` (the renamed native auth SDKs; behavior-equivalent to the matching `0.3.0` session-SDK releases).
- Bumps the Android signals SDK pin to `so.prelude.android:sdk:0.5.2` (was `0.5.0`).

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
- Bumps the iOS dependency to `PreludeAuth` `0.2.0` and the Android dependency to `so.prelude.android:auth-sdk:0.2.0`.

## [0.2.0] - 2026-04-30

### Added
- Android bridge: the full Dart API now works on Android alongside iOS.
- `PreludeFlutterAuthSdkPlugin` (Android) with per-handle native client cache and in-memory step-up challenge cache; the bearer challenge token never crosses the channel.

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
