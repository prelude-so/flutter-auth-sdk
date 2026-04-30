import 'dart:math';

import 'platform_interface.dart';
import 'types/endpoint.dart';
import 'types/otp.dart';
import 'types/password.dart';
import 'types/profile.dart';
import 'types/redacted_string.dart';
import 'types/step_up.dart';
import 'types/user.dart';

/// Client for the Prelude Session API on Flutter.
///
/// Bridges to the native iOS (`PreludeSessionClient` in
/// `PreludeSession`) and Android (`PreludeSessionClient` in
/// `so.prelude.android:sessions`) session SDKs and surfaces their
/// public API through a single Dart entry point.
///
/// Each Dart instance owns a distinct logical session: the SDK
/// stamps an opaque handle at construction time and forwards it
/// with every method call. The native plugin lazily creates one
/// `PreludeSessionClient` per handle on first use and reuses it,
/// so per-instance state — DPoP keys, refresh tokens,
/// access-token caches — stays stable across calls.
///
/// Call [dispose] when you're done with an instance so the native
/// client can be released. Forgetting to dispose leaks the native
/// client until the process exits; nothing else breaks.
///
/// > **Android:** `0.1.0` ships iOS-only feature coverage. Every
/// > non-trivial method throws `MissingPluginException` /
/// > `UnimplementedError` on Android until
/// > `so.prelude.android:sessions` is wired up in a future release.
class PreludeSessionClient {
  /// Creates a session client.
  ///
  /// [endpoint] is the API endpoint. Defaults to
  /// [Endpoint.defaultEndpoint] (the canonical Prelude address);
  /// pass [Endpoint.custom] for staging or local development.
  ///
  /// [hostOverride] is the canonical-authority hint used as the
  /// DPoP `htu`, the `Host:` header, and the Keychain partition
  /// key on iOS. Set when the connection address differs from
  /// what the server sees (e.g. localhost behind a reverse
  /// proxy). `null` derives it from the endpoint's host.
  ///
  /// [timeout] is the per-request network timeout. Defaults to 10
  /// seconds.
  ///
  /// [allowInsecureTLS] tells the native client to trust every
  /// server cert. Local development only — never ship `true`.
  PreludeSessionClient({
    Endpoint endpoint = Endpoint.defaultEndpoint,
    String? hostOverride,
    Duration timeout = const Duration(seconds: 10),
    bool allowInsecureTLS = false,
  }) : _config = ClientConfig(
         endpoint: endpoint,
         hostOverride: hostOverride,
         timeoutSeconds:
             timeout.inMicroseconds / Duration.microsecondsPerSecond,
         allowInsecureTLS: allowInsecureTLS,
       );

  /// Opaque per-instance handle, stable for the lifetime of this
  /// Dart instance. The native plugin uses it to look up the
  /// matching `PreludeSessionClient` for each call.
  final String _handle = _newHandle();
  final ClientConfig _config;

  /// `true` once [dispose] has been called. Subsequent method
  /// calls throw [StateError] so silent leaks turn loud.
  bool _disposed = false;

  static PreludeSessionClientPlatform get _platform =>
      PreludeSessionClientPlatform.instance;

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
    return PreludeSessionClient.validate(
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
  // Step-up
  // ------------------------------------------------------------

  /// Request a step-up to [scope]. Returns the challenge handle —
  /// pass it back to [submitStepUpOTP] together with the OTP code.
  Future<StepUpChallenge> requestStepUp({required String scope}) {
    _ensureNotDisposed();
    return _platform.requestStepUp(
      handle: _handle,
      config: _config,
      scope: scope,
    );
  }

  /// Submit an OTP [code] for [challenge]. Returns the next
  /// challenge for multi-step flows, or `null` when the flow has
  /// completed and the session has been refreshed with the
  /// granted scope.
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
        'PreludeSessionClient has been disposed. Create a new instance '
        'to start a new logical session.',
      );
    }
  }
}

/// Unicode general-category regexes used by [PreludeSessionClient.validate].
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
