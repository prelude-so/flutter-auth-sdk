import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:prelude_flutter_auth_sdk/prelude_flutter_auth_sdk.dart';
import 'package:prelude_flutter_auth_sdk/src/platform_interface.dart';

/// Tests the Dart-only behaviour of [PreludeAuthClient] —
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
    PreludeAuthClientPlatform.instance = fake;
  });

  group('handle stability', () {
    test('every call carries the same handle for one Dart instance', () async {
      final client = PreludeAuthClient(endpoint: const Endpoint.custom('https://x'));
      await client.startOTPLogin(
        StartOTPLoginOptions(identifier: PreludeIdentifier.emailAddress('a@b.c')),
      );
      await client.resendOTP();
      await client.logout();

      final handles = fake.calls.map((c) => c.handle).toSet();
      expect(handles.length, 1);
    });

    test('two instances get different handles', () async {
      final a = PreludeAuthClient(endpoint: const Endpoint.custom('https://x'));
      final b = PreludeAuthClient(endpoint: const Endpoint.custom('https://x'));
      await a.resendOTP();
      await b.resendOTP();
      expect(fake.calls.map((c) => c.handle).toSet().length, 2);
    });
  });

  group('dispose', () {
    test('is idempotent', () async {
      final client = PreludeAuthClient(endpoint: const Endpoint.custom('https://x'));
      await client.dispose();
      await client.dispose(); // must not throw
      // Only one underlying dispose call reaches the platform.
      expect(
        fake.calls.where((c) => c.method == 'dispose').length,
        1,
      );
    });

    test('post-dispose calls throw StateError', () async {
      final client = PreludeAuthClient(endpoint: const Endpoint.custom('https://x'));
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

      final client = PreludeAuthClient(endpoint: const Endpoint.custom('https://x'));
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
      final client = PreludeAuthClient(endpoint: const Endpoint.custom('https://x'));
      await client.changePassword(const RedactedString('hunter2'));
      final call = fake.calls.single;
      expect(call.method, 'changePassword');
      expect(call.args['newPassword'], isA<RedactedString>());
      expect((call.args['newPassword'] as RedactedString).value, 'hunter2');
    });
  });

  group('listSessions', () {
    test('passes options through and returns the platform response', () async {
      final view = PreludeSessionView(
        id: 'ses_1',
        deviceModel: 'Pixel 8',
        deviceType: PreludeDeviceType.mobile,
        osVersion: 'Android 14',
        countryCode: 'SE',
        createdAt: DateTime.utc(2026, 5, 1),
        lastSeenAt: DateTime.utc(2026, 5, 4),
        expiresAt: DateTime.utc(2026, 6, 1),
      );
      fake.listSessionsReply = PreludeListSessionsResponse(
        sessions: [view],
        total: 1,
        limit: 25,
        offset: 0,
      );

      final client = PreludeAuthClient(
        endpoint: const Endpoint.custom('https://x'),
      );
      final res = await client.listSessions(
        PreludeListSessionsOptions(limit: 25, offset: 0),
      );

      expect(res.sessions.single, view);
      expect(res.total, 1);
      final call = fake.calls.single;
      expect(call.method, 'listSessions');
      final opts = call.args['options']! as PreludeListSessionsOptions;
      expect(opts.limit, 25);
      expect(opts.offset, 0);
    });

    test('omitting options forwards an empty toJson', () async {
      final client = PreludeAuthClient(
        endpoint: const Endpoint.custom('https://x'),
      );
      await client.listSessions();
      final opts = fake.calls.single.args['options']!
          as PreludeListSessionsOptions;
      expect(opts.toJson(), isEmpty);
    });
  });

  group('revokeSessions', () {
    test('forwards each target shape verbatim', () async {
      final client = PreludeAuthClient(
        endpoint: const Endpoint.custom('https://x'),
      );
      await client.revokeSessions(PreludeRevokeTarget.all);
      await client.revokeSessions(PreludeRevokeTarget.others);
      await client.revokeSessions(PreludeRevokeTarget.mine);
      await client.revokeSessions(PreludeRevokeTarget.session('ses_42'));

      final targets = fake.calls
          .where((c) => c.method == 'revokeSessions')
          .map((c) => c.args['target']! as PreludeRevokeTarget)
          .toList();
      expect(targets[0], PreludeRevokeTarget.all);
      expect(targets[1], PreludeRevokeTarget.others);
      expect(targets[2], PreludeRevokeTarget.mine);
      expect(targets[3].toJson(), {'kind': 'session', 'sessionID': 'ses_42'});
    });

    test('rejects empty / whitespace-only session ids', () {
      expect(
        () => PreludeRevokeTarget.session(''),
        throwsArgumentError,
      );
      expect(
        () => PreludeRevokeTarget.session('   '),
        throwsArgumentError,
      );
    });
  });

  group('step-up', () {
    test('requestStepUp returns the platform challenge without firing /otp', () async {
      final client = PreludeAuthClient(endpoint: const Endpoint.custom('https://x'));
      final challenge = await client.requestStepUp(scope: 'prld:pwd:write');
      expect(challenge.challengeID, 'cid_1');
      expect(
        fake.calls.where((c) => c.method == 'sendStepUpOTP'),
        isEmpty,
        reason: 'requestStepUp must not fire sendStepUpOTP itself; '
            'the caller drives delivery',
      );
    });

    test('sendStepUpOTP forwards the challenge to the platform', () async {
      final client = PreludeAuthClient(endpoint: const Endpoint.custom('https://x'));
      final challenge = await client.requestStepUp(scope: 'prld:pwd:write');
      await client.sendStepUpOTP(challenge);

      final sends = fake.calls.where((c) => c.method == 'sendStepUpOTP').toList();
      expect(sends, hasLength(1));
      expect(sends.single.args['challenge'], same(challenge));
    });

    test('sendStepUpOTP throws after dispose without hitting the platform', () async {
      final client = PreludeAuthClient(endpoint: const Endpoint.custom('https://x'));
      final challenge = await client.requestStepUp(scope: 'prld:pwd:write');
      await client.dispose();
      expect(
        () => client.sendStepUpOTP(challenge),
        throwsA(isA<StateError>()),
      );
      expect(
        fake.calls.where((c) => c.method == 'sendStepUpOTP'),
        isEmpty,
        reason: 'dispose-time short-circuit must precede any platform call',
      );
    });

    test('requestStepUp forwards metadata when supplied', () async {
      final client = PreludeAuthClient(endpoint: const Endpoint.custom('https://x'));
      await client.requestStepUp(
        scope: 'prld:pwd:write',
        metadata: const {'reason': 'pwd-rotate', 'origin': 'settings'},
      );
      final call = fake.calls.singleWhere((c) => c.method == 'requestStepUp');
      expect(
        call.args['metadata'],
        const {'reason': 'pwd-rotate', 'origin': 'settings'},
      );
    });

    test('requestStepUp omits metadata when null', () async {
      final client = PreludeAuthClient(endpoint: const Endpoint.custom('https://x'));
      await client.requestStepUp(scope: 'prld:pwd:write');
      final call = fake.calls.singleWhere((c) => c.method == 'requestStepUp');
      expect(call.args.containsKey('metadata'), isFalse);
    });

    test('getActiveStepUp round-trips through the platform', () async {
      final client = PreludeAuthClient(endpoint: const Endpoint.custom('https://x'));
      final result = await client.getActiveStepUp();
      expect(result, isNull);
      final calls = fake.calls.where((c) => c.method == 'getActiveStepUp');
      expect(calls, hasLength(1));
    });
  });
}

/// Records every platform call and replays canned responses where
/// the public API needs them.
class _RecordingPlatform extends PreludeAuthClientPlatform
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

  /// Used by [listSessions] tests.
  PreludeListSessionsResponse listSessionsReply =
      const PreludeListSessionsResponse(
        sessions: [],
        total: 0,
        limit: 0,
        offset: 0,
      );

  @override
  Future<PreludeListSessionsResponse> listSessions({
    required String handle,
    required ClientConfig config,
    required PreludeListSessionsOptions options,
  }) async {
    _record('listSessions', handle: handle, args: {'options': options});
    return listSessionsReply;
  }

  @override
  Future<void> revokeSessions({
    required String handle,
    required ClientConfig config,
    required PreludeRevokeTarget target,
  }) async {
    _record('revokeSessions', handle: handle, args: {'target': target});
  }

  @override
  Future<StepUpChallenge> requestStepUp({
    required String handle,
    required ClientConfig config,
    required String scope,
    Map<String, String>? metadata,
  }) async {
    _record(
      'requestStepUp',
      handle: handle,
      args: {'scope': scope, 'metadata': ?metadata},
    );
    return StepUpChallenge.fromJson({
      'status': 'continue',
      'challengeID': 'cid_1',
      'currentStep': 'verify_email',
      'requestedScope': scope,
    });
  }

  @override
  Future<StepUpChallenge?> getActiveStepUp({
    required String handle,
    required ClientConfig config,
  }) async {
    _record('getActiveStepUp', handle: handle);
    return null;
  }

  @override
  Future<void> sendStepUpOTP({
    required String handle,
    required ClientConfig config,
    required StepUpChallenge challenge,
  }) async {
    _record(
      'sendStepUpOTP',
      handle: handle,
      args: {'challenge': challenge},
    );
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
