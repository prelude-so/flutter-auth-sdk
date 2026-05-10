import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prelude_flutter_session_sdk/prelude_flutter_session_sdk.dart';

/// Verifies the Dart-side plumbing of `signalsKeyOverride`.
///
/// We assert at the `MethodChannel` boundary — the same payload
/// the iOS and Android plugins decode in production — so the test
/// catches a regression in either the constructor wiring or the
/// `ClientConfig.toJson` mapping.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('prelude_so_flutter_session_sdk');
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Map<Object?, Object?> configFor(MethodCall call) {
    final args = call.arguments as Map<Object?, Object?>;
    return args['config']! as Map<Object?, Object?>;
  }

  test('omitting signalsKeyOverride forwards null', () async {
    final client = PreludeSessionClient(
      endpoint: const Endpoint.custom('https://x'),
    );
    await client.resendOTP();
    expect(configFor(calls.single)['signalsKeyOverride'], isNull);
  });

  test('non-null override is forwarded verbatim', () async {
    final client = PreludeSessionClient(
      endpoint: const Endpoint.custom('https://x'),
      signalsKeyOverride: 'sdk_test_123',
    );
    await client.resendOTP();
    expect(
      configFor(calls.single)['signalsKeyOverride'],
      'sdk_test_123',
    );
  });

  test('override survives across multiple calls on the same client', () async {
    final client = PreludeSessionClient(
      endpoint: const Endpoint.custom('https://x'),
      signalsKeyOverride: 'sdk_test_abc',
    );
    await client.resendOTP();
    await client.logout();
    expect(calls.length, 2);
    for (final call in calls) {
      expect(configFor(call)['signalsKeyOverride'], 'sdk_test_abc');
    }
  });
}
