import 'json_value.dart';

/// A decoded user profile sourced from the current access token's
/// JWT claims.
class PreludeProfile {
  const PreludeProfile({
    this.userID,
    this.sessionID,
    this.extras = const {},
  });

  /// Stable user identifier — the JWT `sub` claim.
  final String? userID;

  /// Session identifier — the JWT `sid` claim.
  final String? sessionID;

  /// All other top-level claims, with JSON shape preserved (so
  /// large 64-bit integer claims survive intact).
  final Map<String, PreludeJSONValue> extras;

  Map<String, Object?> toJson() => {
    'userID': userID,
    'sessionID': sessionID,
    'extras': {for (final e in extras.entries) e.key: e.value.toJson()},
  };

  factory PreludeProfile.fromJson(Map<Object?, Object?> json) {
    final extrasRaw = (json['extras'] as Map?) ?? const {};
    return PreludeProfile(
      userID: json['userID'] as String?,
      sessionID: json['sessionID'] as String?,
      extras: {
        for (final e in extrasRaw.entries)
          e.key! as String: PreludeJSONValue.fromJson(e.value),
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PreludeProfile &&
      other.userID == userID &&
      other.sessionID == sessionID &&
      _mapEquals(other.extras, extras);

  @override
  int get hashCode => Object.hash(userID, sessionID, _mapHash(extras));

  @override
  String toString() =>
      'PreludeProfile(userID: $userID, sessionID: $sessionID, '
      'extras: ${extras.length} keys)';
}

bool _mapEquals(
  Map<String, PreludeJSONValue> a,
  Map<String, PreludeJSONValue> b,
) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}

int _mapHash(Map<String, PreludeJSONValue> m) =>
    Object.hashAllUnordered(m.entries.map((e) => Object.hash(e.key, e.value)));
