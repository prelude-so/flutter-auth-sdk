# Readme

### Usage

The Flutter Auth SDK lets you sign users into your Flutter app and manages the resulting session — tokens, refresh, logout, step-up — against the Prelude Auth API on iOS and Android.

It is provided as a regular Flutter plugin that you can add as a dependency in your app's `pubspec.yaml`:

```yaml
dependencies:
  prelude_flutter_auth_sdk: ^0.7.0
```

```bash
flutter pub add prelude_flutter_auth_sdk
```

### Requirements

- iOS deployment target **15.1+**
- Android minimum SDK **API 26**
- Dart **3.9.2+** (`^3.9.2`) / Flutter **3.35+**

The plugin pulls the native SDKs in for you — `pod install` downloads `PreludeAuth` (and `Prelude`, the signals SDK) on iOS, and Gradle resolves `so.prelude.android:auth-sdk` (plus `so.prelude.android:sdk` for signals) from Maven Central on Android. Nothing else to add to your project — no extra coordinates in your iOS Podfile or Android `build.gradle`.

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

#### Social login (Google)

Open the provider's page in a system web session and establish a session in one call. The provider page collects credentials — no email/password input in your UI. The `redirectUri` must use your app's custom URL scheme and be allowlisted in your project's OAuth configuration.

```dart
final result = await client.loginWithOAuth(
  OAuthLoginOptions(
    provider: OAuthProvider.google,
    redirectUri: 'myapp://oauth-callback',
  ),
);

switch (result) {
  case OAuthLoggedIn(:final user):
    // signed in
  case OAuthOtpRequired(:final challenge, :final email):
    // provider email unverified (e.g. Microsoft) — a code was sent
    // to `email`; complete the login with the code the user types:
    final user = await client.checkOAuthEmailOTP(challenge, code);
}
```

A dismissed page throws `CancelledException` — typically swallowed rather than surfaced as an error. For apps that present their own web session, `initiateOAuthLogin` returns the authorization `Uri` and `finalizeOAuthLogin(challengeToken)` redeems the callback.

Platform setup:

- **iOS** — no extra configuration; the web session intercepts the redirect scheme directly.
- **Android** — social login opens a Chrome Custom Tab. Add `androidx.browser` to `android/app/build.gradle.kts` and declare the redirect target in `android/app/src/main/AndroidManifest.xml`, with the `data` scheme matching your `redirectUri`:

  ```kotlin
  dependencies {
      implementation("androidx.browser:browser:1.8.0")
  }
  ```

  ```xml
  <activity
      android:name="so.prelude.android.auth.social.OAuthRedirectActivity"
      android:exported="true"
      android:launchMode="singleTask"
      android:theme="@android:style/Theme.Translucent.NoTitleBar">
      <intent-filter>
          <action android:name="android.intent.action.VIEW" />
          <category android:name="android.intent.category.DEFAULT" />
          <category android:name="android.intent.category.BROWSABLE" />
          <data android:scheme="myapp" />
      </intent-filter>
  </activity>
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

When `challenge.currentStep` is `verify_passkey`, advance it with the platform authenticator instead of a code:

```dart
final next = await client.continueStepUpWithPasskey(challenge);
```

#### Passkeys

Sign in with a passkey — no email, no code. The authenticator picks the account:

```dart
final user = await client.loginWithPasskey();
```

Registering one needs a session holding `prld:passkey:write`, granted by a step-up. The grant must be session- or profile-bound; a single-use grant is not honored:

```dart
final challenge = await client.requestStepUp(scope: 'prld:passkey:write');
await client.sendStepUpOTP(challenge);
await client.submitStepUpOTP(challenge, '123456');

final result = await client.registerPasskey(
  RegisterPasskeyOptions(username: 'alice@example.com', nickname: 'iPhone'),
);
// `result.alreadyRegistered` is true when the server already held it.
```

Management, also gated on `prld:passkey:write`:

```dart
final credentials = await client.listPasskeys();
await client.renamePasskey(credentials.first.credentialID, 'Work phone');
await client.deletePasskey(credentials.first.credentialID);
```

A dismissed sheet throws `CancelledException`; a device that can't run a ceremony throws `PasskeyNotSupportedException`.

Platform setup — the OS verifies the app's association with the relying-party host before any ceremony, so both halves are required:

- **iOS 16+** — add the `webcredentials:<rp-id>` associated-domains entitlement, where `<rp-id>` is the host serving `/.well-known/apple-app-site-association`. Register the app's `<TeamID>.<bundleID>` in your project's passkey configuration.

- **Android API 28+** — the Credential Manager is `compileOnly` in the native SDK, so add it in `android/app/build.gradle.kts` (the play-services provider is required below API 34):

  ```kotlin
  dependencies {
      implementation("androidx.credentials:credentials:1.5.0")
      implementation("androidx.credentials:credentials-play-services-auth:1.5.0")
  }
  ```

  Then declare the Digital Asset Links statement in `android/app/src/main/AndroidManifest.xml` and register the app's package name and signing-key SHA-256 fingerprint in your passkey configuration:

  ```xml
  <meta-data
      android:name="asset_statements"
      android:resource="@string/asset_statements" />
  ```

  ```xml
  <!-- res/values/strings.xml -->
  <string name="asset_statements" translatable="false">
      [{\"include\":\"https://&lt;rp-id&gt;/.well-known/assetlinks.json\"}]
  </string>
  ```

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
