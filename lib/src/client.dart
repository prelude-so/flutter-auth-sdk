import 'dart:math';

import 'platform_interface.dart';
import 'types/endpoint.dart';
import 'types/migrate.dart';
import 'types/oauth.dart';
import 'types/otp.dart';
import 'types/password.dart';
import 'types/profile.dart';
import 'types/redacted_string.dart';
import 'types/sessions.dart';
import 'types/step_up.dart';
import 'types/user.dart';

/// Client for the Prelude Auth API on Flutter.
///
/// Each Dart instance owns a distinct logical session: the SDK
/// stamps an opaque handle at construction time and forwards it
/// with every method call. The native plugin lazily creates one
/// auth client per handle on first use and reuses it,
/// so per-instance state — DPoP keys, refresh tokens,
/// access-token caches — stays stable across calls.
///
/// Call [dispose] when you're done with an instance so the native
/// client can be released. Forgetting to dispose leaks the native
/// client until the process exits; nothing else breaks.
class PreludeAuthClient {
  /// Creates an auth client.
  ///
  /// [endpoint] is the API endpoint. Defaults to
  /// [Endpoint.defaultEndpoint] (the canonical Prelude address);
  /// pass [Endpoint.custom] for staging or local development.
  ///
  /// [hostOverride] is the canonical-authority hint used as the
  /// DPoP `htu`, the `Host:` header, and the per-domain partition
  /// key for the native credential store. Set when the connection
  /// address differs from what the server sees (e.g. localhost
  /// behind a reverse proxy). `null` derives it from the
  /// endpoint's host.
  ///
  /// [timeout] is the per-request network timeout. Defaults to 10
  /// seconds.
  ///
  /// [allowInsecureTLS] tells the native client to trust every
  /// server cert. Local development only — never ship `true`.
  ///
  /// [signalsKeyOverride] forces a specific Prelude signals SDK
  /// key for this client, bypassing the platform manifest. The
  /// default path is to leave this `null` and configure the key
  /// per-platform: `PreludeSDKKey` in `Info.plist` on iOS,
  /// `<meta-data android:name="so.prelude.sdk_key">` in
  /// `AndroidManifest.xml` on Android — that way the iOS key
  /// can't ship in an Android build, and vice versa. The override
  /// is for runtime-fetched config (CI, white-label) where a
  /// Dart-side string is genuinely the right shape.
  PreludeAuthClient({
    Endpoint endpoint = Endpoint.defaultEndpoint,
    String? hostOverride,
    Duration timeout = const Duration(seconds: 10),
    bool allowInsecureTLS = false,
    String? signalsKeyOverride,
  }) : _config = ClientConfig(
         endpoint: endpoint,
         hostOverride: hostOverride,
         timeoutSeconds:
             timeout.inMicroseconds / Duration.microsecondsPerSecond,
         allowInsecureTLS: allowInsecureTLS,
         signalsKeyOverride: signalsKeyOverride,
       );

  /// Opaque per-instance handle, stable for the lifetime of this
  /// Dart instance. The native plugin uses it to look up the
  /// matching `PreludeAuthClient` for each call.
  final String _handle = _newHandle();
  final ClientConfig _config;

  /// `true` once [dispose] has been called. Subsequent method
  /// calls throw [StateError] so silent leaks turn loud.
  bool _disposed = false;

  static PreludeAuthClientPlatform get _platform =>
      PreludeAuthClientPlatform.instance;

  /// Native SDK platform version. Channel smoke test.
  Future<String?> getPlatformVersion() {
    _ensureNotDisposed();
    return _platform.getPlatformVersion();
  }

  /// Release native state owned by this client. Idempotent.
  /// After this returns, every other method on the instance
  /// throws [StateError].
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _platform.dispose(handle: _handle);
  }

  // ------------------------------------------------------------
  // OTP
  // ------------------------------------------------------------

  /// Start an OTP login by sending a one-time code to
  /// [StartOTPLoginOptions.identifier]. Unauthenticated.
  Future<void> startOTPLogin(StartOTPLoginOptions options) {
    _ensureNotDisposed();
    return _platform.startOTPLogin(
      handle: _handle,
      config: _config,
      options: options,
    );
  }

  /// Ask the server to resend the most recently issued OTP.
  Future<void> resendOTP() {
    _ensureNotDisposed();
    return _platform.resendOTP(handle: _handle, config: _config);
  }

  /// Submit an OTP [code] to complete the login flow. Returns the
  /// authenticated user.
  Future<PreludeUser> checkOTP(String code) {
    _ensureNotDisposed();
    return _platform.checkOTP(
      handle: _handle,
      config: _config,
      code: code,
    );
  }

  // ------------------------------------------------------------
  // Password
  // ------------------------------------------------------------

  /// Log in with an email identifier and a password.
  Future<PreludeUser> loginWithPassword(LoginWithPasswordOptions options) {
    _ensureNotDisposed();
    return _platform.loginWithPassword(
      handle: _handle,
      config: _config,
      options: options,
    );
  }

  /// Fetch the server's password compliancy rules.
  /// Unauthenticated — the rules are public configuration.
  Future<PreludePasswordCompliancy> passwordCompliancy() {
    _ensureNotDisposed();
    return _platform.passwordCompliancy(handle: _handle, config: _config);
  }

  /// Validate a candidate password against the server's
  /// compliancy rules. Fetches [passwordCompliancy] once and then
  /// classifies locally — no per-call round-trip. For real-time
  /// validation
  /// (e.g. on every keystroke), call [passwordCompliancy] once,
  /// keep the result, and run [validate] synchronously.
  Future<PreludePasswordCompliancyResults> validatePassword(
    String password,
  ) async {
    _ensureNotDisposed();
    final compliancy = await passwordCompliancy();
    return PreludeAuthClient.validate(
      password: password,
      against: compliancy,
    );
  }

  /// Classify [password] against [against] using Unicode
  /// general-category rules. Pure; safe to call on every keystroke
  /// once a [PreludePasswordCompliancy] has been fetched.
  ///
  /// Length is counted in Unicode code points, not Dart's UTF-16
  /// `length`, so emoji and astral-plane characters count as one.
  static PreludePasswordCompliancyResults validate({
    required String password,
    required PreludePasswordCompliancy against,
  }) {
    final upper = _upperRegex.allMatches(password).length;
    final lower = _lowerRegex.allMatches(password).length;
    final numbers = _digitRegex.allMatches(password).length;
    final total = password.runes.length;
    // Anything not Lu/Ll/Nd is treated as a symbol.
    final symbols = total - upper - lower - numbers;

    final results = <PreludePasswordCompliancyResult>[
      PreludePasswordCompliancyResult(
        criterion: PreludePasswordCompliancyCriterion.minLength,
        actual: total,
        expected: against.minLength,
        valid: total >= against.minLength,
      ),
      PreludePasswordCompliancyResult(
        criterion: PreludePasswordCompliancyCriterion.maxLength,
        actual: total,
        expected: against.maxLength,
        // 0 is the "no upper bound" sentinel.
        valid: against.maxLength == 0 || total <= against.maxLength,
      ),
      PreludePasswordCompliancyResult(
        criterion: PreludePasswordCompliancyCriterion.uppercase,
        actual: upper,
        expected: against.uppercase,
        valid: upper >= against.uppercase,
      ),
      PreludePasswordCompliancyResult(
        criterion: PreludePasswordCompliancyCriterion.lowercase,
        actual: lower,
        expected: against.lowercase,
        valid: lower >= against.lowercase,
      ),
      PreludePasswordCompliancyResult(
        criterion: PreludePasswordCompliancyCriterion.numbers,
        actual: numbers,
        expected: against.numbers,
        valid: numbers >= against.numbers,
      ),
      PreludePasswordCompliancyResult(
        criterion: PreludePasswordCompliancyCriterion.symbols,
        actual: symbols,
        expected: against.symbols,
        valid: symbols >= against.symbols,
      ),
    ];

    return PreludePasswordCompliancyResults(
      valid: results.every((r) => r.valid),
      results: results,
    );
  }

  /// Change the currently authenticated user's password. Requires
  /// the session to carry `prld:pwd:write` — obtain it via
  /// [requestStepUp] + [submitStepUpOTP]. Sessions without it
  /// throw [InsufficientScopeException].
  ///
  /// The password is taken as a [RedactedString] so it never
  /// leaks through `toString` / `print` at the call site.
  Future<void> changePassword(RedactedString newPassword) {
    _ensureNotDisposed();
    return _platform.changePassword(
      handle: _handle,
      config: _config,
      newPassword: newPassword,
    );
  }

  /// Whether the current session can call [changePassword]
  /// without going through step-up first — i.e. whether its
  /// access token already carries `prld:pwd:write`.
  ///
  /// Call before driving a "change password" UI to decide
  /// whether to prompt for step-up. Throws if the session
  /// refresh fails; returns `false` when the refreshed token
  /// lacks the scope or the claim is missing/malformed.
  Future<bool> canChangePassword() {
    _ensureNotDisposed();
    return _platform.canChangePassword(handle: _handle, config: _config);
  }

  // ------------------------------------------------------------
  // Migration
  // ------------------------------------------------------------

  /// Exchange a legacy bearer token for a Prelude session,
  /// returning the authenticated user.
  ///
  /// Safe to call on every launch: a valid cached session returns
  /// immediately without spending the legacy token, and concurrent
  /// callers share a single in-flight exchange.
  Future<PreludeUser> migrate(MigrateOptions options) {
    _ensureNotDisposed();
    return _platform.migrate(
      handle: _handle,
      config: _config,
      options: options,
    );
  }

  // ------------------------------------------------------------
  // Social / OAuth login
  // ------------------------------------------------------------

  /// Authenticate against an identity provider in a system web
  /// session and establish a session. One-shot: presents the
  /// provider page natively and redeems the callback.
  ///
  /// Only one login can be presented at a time; a concurrent call
  /// throws [ConflictException]. A dismissed page throws
  /// [CancelledException].
  ///
  /// [OAuthLoginOptions.redirectUri] must use the app's custom URL
  /// scheme; an `http`/`https` URI throws
  /// [InvalidConfigurationException] before any network call.
  Future<FinalizeOAuthLoginResult> loginWithOAuth(OAuthLoginOptions options) {
    _ensureNotDisposed();
    return _platform.loginWithOAuth(
      handle: _handle,
      config: _config,
      options: options,
    );
  }

  /// Request a provider authorization URL to present in a web
  /// authentication context yourself.
  ///
  /// Generates a PKCE pair held natively until
  /// [finalizeOAuthLogin] redeems it; a new call supersedes any
  /// unredeemed earlier attempt. Pair with [finalizeOAuthLogin]
  /// when the app presents its own web session instead of
  /// [loginWithOAuth].
  Future<Uri> initiateOAuthLogin(InitiateOAuthLoginOptions options) {
    _ensureNotDisposed();
    return _platform.initiateOAuthLogin(
      handle: _handle,
      config: _config,
      options: options,
    );
  }

  /// Redeem the `challenge_token` delivered to the redirect URI
  /// and establish a session.
  ///
  /// Throws [MissingChallengeTokenException] for an empty token
  /// and [InvalidChallengeTokenException] for a malformed one.
  Future<FinalizeOAuthLoginResult> finalizeOAuthLogin(String challengeToken) {
    _ensureNotDisposed();
    return _platform.finalizeOAuthLogin(
      handle: _handle,
      config: _config,
      challengeToken: challengeToken,
    );
  }

  /// Complete an OAuth login whose provider email needs verifying.
  ///
  /// Pass the [OAuthEmailChallenge] from an [OAuthOtpRequired]
  /// result together with the [code] the user received. Returns the
  /// authenticated user. The challenge is single-use; an
  /// [InvalidOTPCodeException] leaves it valid for another attempt,
  /// any other error retires it.
  Future<PreludeUser> checkOAuthEmailOTP(
    OAuthEmailChallenge challenge,
    String code,
  ) {
    _ensureNotDisposed();
    return _platform.checkOAuthEmailOTP(
      handle: _handle,
      config: _config,
      challenge: challenge,
      code: code,
    );
  }

  // ------------------------------------------------------------
  // Refresh / logout / invalidate
  // ------------------------------------------------------------

  /// Return an authenticated [PreludeUser], refreshing the access
  /// token if the cached one has expired. Concurrent callers
  /// share a single in-flight refresh.
  Future<PreludeUser> refresh() {
    _ensureNotDisposed();
    return _platform.refresh(handle: _handle, config: _config);
  }

  /// Revoke the session server-side and wipe local credentials.
  Future<void> logout() {
    _ensureNotDisposed();
    return _platform.logout(handle: _handle, config: _config);
  }

  /// Mark the local access token expired so the next protected
  /// call refreshes. Does NOT revoke the session on the server or
  /// wipe the refresh token — use [logout] for that.
  Future<void> invalidateSession() {
    _ensureNotDisposed();
    return _platform.invalidateSession(handle: _handle, config: _config);
  }

  // ------------------------------------------------------------
  // Manage sessions (list / revoke)
  // ------------------------------------------------------------

  /// Fetch a page of active sessions for the authenticated user.
  /// Both [PreludeListSessionsOptions.limit] and
  /// [PreludeListSessionsOptions.offset] are optional — the server
  /// applies its own defaults when absent so a default change lands
  /// without a client release.
  Future<PreludeListSessionsResponse> listSessions([
    PreludeListSessionsOptions? options,
  ]) {
    _ensureNotDisposed();
    return _platform.listSessions(
      handle: _handle,
      config: _config,
      options: options ?? PreludeListSessionsOptions(),
    );
  }

  /// Revoke one or more of the authenticated user's sessions.
  ///
  /// When [target] kills the calling session
  /// ([PreludeRevokeTarget.all], [PreludeRevokeTarget.mine], or a
  /// [PreludeRevokeTarget.session] whose id matches the cached
  /// session), the native SDK additionally wipes the per-domain
  /// credential stores — same wipe [logout] performs — so a stale
  /// refresh can't resurrect them.
  Future<void> revokeSessions(PreludeRevokeTarget target) {
    _ensureNotDisposed();
    return _platform.revokeSessions(
      handle: _handle,
      config: _config,
      target: target,
    );
  }

  // ------------------------------------------------------------
  // Step-up
  // ------------------------------------------------------------

  /// Request a step-up to [scope]. Returns the challenge handle —
  /// pass it to [sendStepUpOTP] to trigger code delivery, then to
  /// [submitStepUpOTP] together with the OTP code.
  ///
  /// This call never fires `POST /otp` itself, so callers driving
  /// a "resend code" button or a multi-screen UI keep full control
  /// over delivery timing.
  ///
  /// [metadata] is forwarded verbatim to the server's step-up audit
  /// hook. Server caps apply (max 5 keys, 12-char keys, 32-char
  /// values); a violation surfaces as [BadRequestException].
  Future<StepUpChallenge> requestStepUp({
    required String scope,
    Map<String, String>? metadata,
  }) {
    _ensureNotDisposed();
    return _platform.requestStepUp(
      handle: _handle,
      config: _config,
      scope: scope,
      metadata: metadata,
    );
  }

  /// Most recent in-flight step-up challenge for this client, or
  /// `null` if none. Mirrors the native accessor — useful for UIs
  /// that resume a step-up flow across screens without threading
  /// the [StepUpChallenge] handle through their state.
  Future<StepUpChallenge?> getActiveStepUp() {
    _ensureNotDisposed();
    return _platform.getActiveStepUp(handle: _handle, config: _config);
  }

  /// Trigger OTP delivery (`POST /otp`) for an in-flight step-up
  /// [challenge].
  ///
  /// Call this when [challenge.currentStep] is an OTP-delivery
  /// step (`verify_email` / `verify_sms`) so the user receives the
  /// code. Caller-driven on purpose: the UI decides when delivery
  /// fires.
  ///
  /// Throws an [InvalidChallengeTokenException] if [challenge] is
  /// blocked (carries no token).
  Future<void> sendStepUpOTP(StepUpChallenge challenge) {
    _ensureNotDisposed();
    return _platform.sendStepUpOTP(
      handle: _handle,
      config: _config,
      challenge: challenge,
    );
  }

  /// Submit an OTP [code] for [challenge]. Returns the next
  /// challenge for multi-step flows, or `null` when the flow has
  /// completed and the session has been refreshed with the
  /// granted scope. For a multi-step flow whose next step is also
  /// OTP delivery, the caller must invoke [sendStepUpOTP] on the
  /// returned challenge to trigger the next code.
  Future<StepUpChallenge?> submitStepUpOTP(
    StepUpChallenge challenge,
    String code,
  ) {
    _ensureNotDisposed();
    return _platform.submitStepUpOTP(
      handle: _handle,
      config: _config,
      challenge: challenge,
      code: code,
    );
  }

  // ------------------------------------------------------------
  // Cached session readers
  // ------------------------------------------------------------

  /// Profile claims of the currently cached access token, or
  /// `null` if none. Ignores expiration so the app can render the
  /// profile during a refresh.
  Future<PreludeProfile?> getProfile() {
    _ensureNotDisposed();
    return _platform.getProfile(handle: _handle, config: _config);
  }

  /// Session identifier of the currently cached access token,
  /// sourced from the JWT `sid` claim.
  Future<String?> getSessionID() {
    _ensureNotDisposed();
    return _platform.getSessionID(handle: _handle, config: _config);
  }

  /// Raw cached access token, or `null` if none. Does not check
  /// expiration — production code gets a fresh token wired in
  /// automatically via [refresh] during protected calls.
  Future<String?> getAccessToken() {
    _ensureNotDisposed();
    return _platform.getAccessToken(handle: _handle, config: _config);
  }

  /// Absolute expiration of the cached access token, already
  /// clock-skew-adjusted at storage time. Returns even for expired
  /// tokens so diagnostic UIs can render "expired Ns ago".
  Future<DateTime?> getAccessTokenExpiresAt() {
    _ensureNotDisposed();
    return _platform.getAccessTokenExpiresAt(
      handle: _handle,
      config: _config,
    );
  }

  // ------------------------------------------------------------
  // Internals
  // ------------------------------------------------------------

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError(
        'PreludeAuthClient has been disposed. Create a new instance '
        'to start a new logical session.',
      );
    }
  }
}

/// Unicode general-category regexes used by [PreludeAuthClient.validate].
/// Compiled once at module load — the engine treats `\p{...}` with the
/// `unicode` flag as ECMAScript's Unicode property escapes, matching
/// iOS's `Unicode.Scalar.Properties.generalCategory` arms exactly.
final _upperRegex = RegExp(r'\p{Lu}', unicode: true);
final _lowerRegex = RegExp(r'\p{Ll}', unicode: true);
final _digitRegex = RegExp(r'\p{Nd}', unicode: true);

/// Time-prefixed lower-hex handle. The microsecond prefix keeps
/// ordering stable for log diff-ing; the random tail prevents
/// collisions when two instances are constructed in the same
/// microsecond. We avoid pulling a `uuid` dep for one ID.
final _random = Random.secure();

String _newHandle() {
  final now = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
  final tail = StringBuffer();
  for (var i = 0; i < 16; i++) {
    tail.write(_random.nextInt(16).toRadixString(16));
  }
  return '${now.padLeft(16, '0')}-$tail';
}
