import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:prelude_flutter_session_sdk/prelude_flutter_session_sdk.dart';
import 'package:prelude_flutter_session_sdk/src/platform_interface.dart';

/// Tests the Dart-only behaviour of [PreludeSessionClient] —
/// dispose lifecycle, the local short-circuit for
/// `validatePassword`, and the per-instance handle plumbing.
/// The native plugin is replaced with a recording fake so every
/// call site is observable from the test.
void main() {
  // Re-bind the platform interface for each test so state from
  // one test can't leak into another.
  late _RecordingPlatform fake;

  setUp(() {
    fake = _RecordingPlatform();
    PreludeSessionClientPlatform.instance = fake;
  });

  group('handle stability', () {
    test('every call carries the same handle for one Dart instance', () async {
      final client = PreludeSessionClient(endpoint: const Endpoint.custom('https://x'));
      await client.startOTPLogin(
        StartOTPLoginOptions(identifier: PreludeIdentifier.emailAddress('a@b.c')),
      );
      await client.resendOTP();
      await client.logout();

      final handles = fake.calls.map((c) => c.handle).toSet();
      expect(handles.length, 1);
    });

    test('two instances get different handles', () async {
      final a = PreludeSessionClient(endpoint: const Endpoint.custom('https://x'));
      final b = PreludeSessionClient(endpoint: const Endpoint.custom('https://x'));
      await a.resendOTP();
      await b.resendOTP();
      expect(fake.calls.map((c) => c.handle).toSet().length, 2);
    });
  });

  group('dispose', () {
    test('is idempotent', () async {
      final client = PreludeSessionClient(endpoint: const Endpoint.custom('https://x'));
      await client.dispose();
      await client.dispose(); // must not throw
      // Only one underlying dispose call reaches the platform.
      expect(
        fake.calls.where((c) => c.method == 'dispose').length,
        1,
      );
    });

    test('post-dispose calls throw StateError', () async {
      final client = PreludeSessionClient(endpoint: const Endpoint.custom('https://x'));
      await client.dispose();
      expect(() => client.resendOTP(), throwsStateError);
      expect(() => client.refresh(), throwsStateError);
      expect(() => client.getProfile(), throwsStateError);
    });
  });

  group('validatePassword', () {
    test('fetches compliancy once, classifies locally, no native validate', () async {
      fake.compliancyReply = const PreludePasswordCompliancy(
        minLength: 8,
        maxLength: 0,
        uppercase: 1,
        lowercase: 1,
        numbers: 1,
        symbols: 1,
      );

      final client = PreludeSessionClient(endpoint: const Endpoint.custom('https://x'));
      final results = await client.validatePassword('Abcd1234!');
      expect(results.valid, isTrue);

      // Exactly one network-bound call: passwordCompliancy.
      expect(
        fake.calls.map((c) => c.method).toList(),
        ['passwordCompliancy'],
      );
    });
  });

  group('changePassword', () {
    test('forwards a RedactedString unchanged', () async {
      final client = PreludeSessionClient(endpoint: const Endpoint.custom('https://x'));
      await client.changePassword(const RedactedString('hunter2'));
      final call = fake.calls.single;
      expect(call.method, 'changePassword');
      expect(call.args['newPassword'], isA<RedactedString>());
      expect((call.args['newPassword'] as RedactedString).value, 'hunter2');
    });
  });
}

/// Records every platform call and replays canned responses where
/// the public API needs them.
class _RecordingPlatform extends PreludeSessionClientPlatform
    with MockPlatformInterfaceMixin {
  final List<_Call> calls = [];

  /// Used by [validatePassword]'s passwordCompliancy round-trip.
  PreludePasswordCompliancy compliancyReply = const PreludePasswordCompliancy(
    minLength: 0,
    maxLength: 0,
    uppercase: 0,
    lowercase: 0,
    numbers: 0,
    symbols: 0,
  );

  void _record(
    String method, {
    String? handle,
    Map<String, Object?> args = const <String, Object?>{},
  }) {
    calls.add(_Call(method: method, handle: handle, args: args));
  }

  @override
  Future<String?> getPlatformVersion() async {
    _record('getPlatformVersion');
    return 'fake';
  }

  @override
  Future<void> dispose({required String handle}) async {
    _record('dispose', handle: handle);
  }

  @override
  Future<void> startOTPLogin({
    required String handle,
    required ClientConfig config,
    required StartOTPLoginOptions options,
  }) async {
    _record('startOTPLogin', handle: handle, args: {'options': options});
  }

  @override
  Future<void> resendOTP({required String handle, required ClientConfig config}) async {
    _record('resendOTP', handle: handle);
  }

  @override
  Future<PreludeUser> checkOTP({
    required String handle,
    required ClientConfig config,
    required String code,
  }) async {
    _record('checkOTP', handle: handle, args: {'code': code});
    return _stubUser();
  }

  @override
  Future<PreludeUser> loginWithPassword({
    required String handle,
    required ClientConfig config,
    required LoginWithPasswordOptions options,
  }) async {
    _record('loginWithPassword', handle: handle, args: {'options': options});
    return _stubUser();
  }

  @override
  Future<PreludePasswordCompliancy> passwordCompliancy({
    required String handle,
    required ClientConfig config,
  }) async {
    _record('passwordCompliancy', handle: handle);
    return compliancyReply;
  }

  @override
  Future<void> changePassword({
    required String handle,
    required ClientConfig config,
    required RedactedString newPassword,
  }) async {
    _record(
      'changePassword',
      handle: handle,
      args: {'newPassword': newPassword},
    );
  }

  @override
  Future<PreludeUser> refresh({required String handle, required ClientConfig config}) async {
    _record('refresh', handle: handle);
    return _stubUser();
  }

  @override
  Future<void> logout({required String handle, required ClientConfig config}) async {
    _record('logout', handle: handle);
  }

  @override
  Future<void> invalidateSession({
    required String handle,
    required ClientConfig config,
  }) async {
    _record('invalidateSession', handle: handle);
  }

  @override
  Future<StepUpChallenge> requestStepUp({
    required String handle,
    required ClientConfig config,
    required String scope,
  }) async {
    _record('requestStepUp', handle: handle, args: {'scope': scope});
    return StepUpChallenge.fromJson({
      'status': 'continue',
      'challengeID': 'cid_1',
      'currentStep': 'verify_email',
      'requestedScope': scope,
    });
  }

  @override
  Future<StepUpChallenge?> submitStepUpOTP({
    required String handle,
    required ClientConfig config,
    required StepUpChallenge challenge,
    required String code,
  }) async {
    _record(
      'submitStepUpOTP',
      handle: handle,
      args: {'challenge': challenge, 'code': code},
    );
    return null;
  }

  @override
  Future<PreludeProfile?> getProfile({
    required String handle,
    required ClientConfig config,
  }) async {
    _record('getProfile', handle: handle);
    return null;
  }

  @override
  Future<String?> getSessionID({
    required String handle,
    required ClientConfig config,
  }) async {
    _record('getSessionID', handle: handle);
    return null;
  }

  @override
  Future<String?> getAccessToken({
    required String handle,
    required ClientConfig config,
  }) async {
    _record('getAccessToken', handle: handle);
    return null;
  }

  @override
  Future<DateTime?> getAccessTokenExpiresAt({
    required String handle,
    required ClientConfig config,
  }) async {
    _record('getAccessTokenExpiresAt', handle: handle);
    return null;
  }
}

PreludeUser _stubUser() => const PreludeUser(
      accessToken: 'eyJ.stub.token',
      profile: PreludeProfile(),
    );

class _Call {
  _Call({required this.method, required this.handle, required this.args});
  final String method;
  final String? handle;
  final Map<String, Object?> args;
}
