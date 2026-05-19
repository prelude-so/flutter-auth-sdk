# Readme

### Usage

The Flutter Auth SDK lets you sign users into your Flutter app and manages the resulting session — tokens, refresh, logout, step-up — against the Prelude Auth API on iOS and Android.

It is provided as a regular Flutter plugin that you can add as a dependency in your app's `pubspec.yaml`:

```yaml
dependencies:
  prelude_flutter_auth_sdk: ^0.4.0
```

```bash
flutter pub add prelude_flutter_auth_sdk
```

iOS deployment target: **15.1**. Android minimum SDK: **API 26**. The plugin pulls the native SDKs in for you — `pod install` downloads `PreludeAuth` (and `Prelude`, the signals SDK) on iOS, and Gradle resolves `so.prelude.android:auth-sdk` (plus `so.prelude.android:sdk` for signals) from Maven Central on Android. Nothing else to add to your project — no extra coordinates in your iOS Podfile or Android `build.gradle`.

#### Configure the client

Point the client at your project's Prelude Auth endpoint. Use the production URL in production, and a custom URL for staging or local development.

```dart
import 'package:prelude_flutter_auth_sdk/prelude_flutter_auth_sdk.dart';

final client = PreludeAuthClient(
  endpoint: Endpoint.custom('https://<your-app>.session.prelude.dev'),
);
```

#### Email OTP login

Send a one-time code to the user's email address, then submit the code they entered. The SDK persists the resulting tokens in the platform's secure store (Keychain on iOS, app-private storage on Android).

```dart
await client.startOTPLogin(
  StartOTPLoginOptions(
    identifier: PreludeIdentifier.emailAddress('alice@example.com'),
  ),
);

final user = await client.checkOTP('123456');
```

If the user wants the code resent, call `client.resendOTP()`.

#### Email and password login

```dart
final user = await client.loginWithPassword(
  LoginWithPasswordOptions(
    emailAddress: 'alice@example.com',
    password: 'correct horse battery staple',
  ),
);
```

#### Password validation

One-shot validation against the project's policy:

```dart
final result = await client.validatePassword('candidate');
if (result.valid) {
  // ok to submit
}
```

Or fetch the policy once and classify locally — pure function, safe to call on every keystroke:

```dart
final policy = await client.passwordCompliancy();
final result = PreludeAuthClient.validate(
  password: 'candidate',
  against: policy,
);
```

#### Session lifecycle

```dart
await client.refresh();             // refreshes the access token
await client.logout();              // revokes the session and clears local tokens
await client.invalidateSession();   // marks the local token expired; next protected call refreshes

final profile = await client.getProfile();      // currently signed-in user, if any
final token   = await client.getAccessToken();  // the access token, if any
```

Protected requests auto-refresh expired access tokens transparently, so most apps will not need to call `refresh()` explicitly. `invalidateSession()` is the local-only counterpart — it doesn't touch the server or clear the refresh token, it just forces the next protected call to refresh.

#### Step-up authentication

Some operations (e.g. changing the password) require a fresh proof of identity. Request the scope, deliver the OTP, then submit the code:

```dart
final challenge = await client.requestStepUp(scope: 'prld:pwd:write');
await client.sendStepUpOTP(challenge);                 // POST /otp
final next = await client.submitStepUpOTP(challenge, '123456');

// `next == null` means the flow completed and the session now
// carries the requested scope. A non-null value is the next
// challenge in a multi-step flow — call `sendStepUpOTP` on it
// to deliver the next code.
```

`client.getActiveStepUp()` returns the most recent in-flight challenge so a UI can resume from a cold start.

#### Change password

After completing a step-up for `prld:pwd:write`:

```dart
await client.changePassword(RedactedString('new-password'));
```

The SDK drops the granted scope locally on success so the same token cannot reset the password again.

#### Manage active sessions

List the user's sessions across devices and revoke them individually or in bulk:

```dart
final page = await client.listSessions(
  PreludeListSessionsOptions(limit: 20),
);

await client.revokeSessions(PreludeRevokeTarget.others);              // keep this device, sign out the rest
await client.revokeSessions(PreludeRevokeTarget.session(sessionID));  // revoke a specific session
await client.revokeSessions(PreludeRevokeTarget.all);                 // including this device
```

Revoking the current session (`all`, `mine`, or its specific id) also wipes the local credentials, mirroring `logout()`.

#### Anti-fraud signals

The Prelude signals SDK is bundled and **off by default**. When a key is configured for the running platform, the auth client stamps a Prelude `dispatch_id` onto unauthenticated logins (start OTP, login with password, request step-up). With no key configured, `dispatch_id` is omitted from login bodies and the rest of the flow is unchanged — useful while integrating, recommended to enable for production.

Configuration lives in the native manifest so the iOS key can't ship in an Android build, and vice versa.

iOS — add `PreludeSDKKey` to `ios/Runner/Info.plist`:

```xml
<key>PreludeSDKKey</key>
<string>sdk_ios_XXXXXXXXXXXXXXXX</string>
```

Android — add a `<meta-data>` entry inside `<application>` in `android/app/src/main/AndroidManifest.xml`:

```xml
<meta-data
    android:name="so.prelude.sdk_key"
    android:value="sdk_android_XXXXXXXXXXXXXXXX" />
```

For runtime-fetched configuration (CI, white-label apps), `signalsKeyOverride` on the constructor wins over the manifest:

```dart
final client = PreludeAuthClient(
  endpoint: Endpoint.custom('https://<your-app>.session.prelude.dev'),
  signalsKeyOverride: await myConfig.fetchSignalsKey(),
);
```

#### Disposing the client

Call `dispose()` when you're done with a client so the native session is released:

```dart
await client.dispose();
```

After disposal the instance throws on every subsequent call. Create a new `PreludeAuthClient` to start a fresh logical session.

#### Endpoint configuration

```dart
final client = PreludeAuthClient(
  endpoint: Endpoint.custom('https://<your-app>.session.prelude.dev'),
  timeout: const Duration(seconds: 10),
);
```

Each Prelude project has its own Auth endpoint URL — use the production URL in production, and a custom URL for staging or local development.
