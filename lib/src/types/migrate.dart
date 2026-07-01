import 'redacted_string.dart';

/// Options for [PreludeAuthClient.migrate].
///
/// The legacy bearer token is wrapped in a [RedactedString] so the
/// options object is safe to `print`, `toString`, or surface in
/// error messages. The default constructor accepts a plain
/// `String` for call-site ergonomics — wrapping happens internally.
class MigrateOptions {
  /// Plain-string convenience: wraps [token] in a [RedactedString].
  MigrateOptions(String token) : token = RedactedString(token);

  /// Pre-wrapped variant — use when the token is already held in a
  /// [RedactedString] further up the call stack.
  const MigrateOptions.redacted(this.token);

  /// Bearer token issued by the legacy authentication system. Held
  /// only for the duration of one [PreludeAuthClient.migrate] call;
  /// never persisted by the SDK.
  final RedactedString token;

  Map<String, Object?> toJson() => {'token': token.value};

  @override
  String toString() => 'MigrateOptions(token: $token)';
}
