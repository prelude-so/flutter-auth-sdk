/// Types backing [PreludeSessionClient.listSessions] and
/// [PreludeSessionClient.revokeSessions].
library;

/// Form factor reported by the server for an active session.
///
/// Unknown values from a future server fold into [unknown] rather
/// than throwing — same defensive shape as the rest of the public
/// surface, so an additive server change doesn't break older SDKs.
enum PreludeDeviceType {
  desktop('desktop'),
  mobile('mobile'),
  tablet('tablet'),
  unknown('unknown');

  const PreludeDeviceType(this.wireValue);

  final String wireValue;

  static PreludeDeviceType fromWire(String wire) {
    for (final v in values) {
      if (v.wireValue == wire) return v;
    }
    return PreludeDeviceType.unknown;
  }
}

/// One active session as reported by `GET /me/list`.
///
/// Timestamps are surfaced as [DateTime] (always UTC). The native
/// plugins encode them as ISO 8601 strings on the wire and the
/// Dart side parses up-front, so UI code never has to.
class PreludeSessionView {
  const PreludeSessionView({
    required this.id,
    required this.deviceModel,
    required this.deviceType,
    required this.osVersion,
    required this.countryCode,
    required this.createdAt,
    required this.lastSeenAt,
    required this.expiresAt,
  });

  /// Server-assigned session id; pass to
  /// [PreludeRevokeTarget.session] to revoke a single entry.
  final String id;

  /// Human-readable device label (e.g. `"iPhone 15 Pro"`,
  /// `"Pixel 8"`); empty when the server couldn't infer one.
  final String deviceModel;

  /// Broad device class.
  final PreludeDeviceType deviceType;

  /// OS marketing version (e.g. `"iOS 17.2"`); may be empty.
  final String osVersion;

  /// ISO 3166-1 alpha-2 country code derived from the request IP at
  /// session creation time; may be empty.
  final String countryCode;

  /// When the session was first issued.
  final DateTime createdAt;

  /// Last refresh observed for this session.
  final DateTime lastSeenAt;

  /// Absolute refresh-token expiry. After this instant the session
  /// is implicitly dead even if not explicitly revoked.
  final DateTime expiresAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'deviceModel': deviceModel,
    'deviceType': deviceType.wireValue,
    'osVersion': osVersion,
    'countryCode': countryCode,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'lastSeenAt': lastSeenAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };

  factory PreludeSessionView.fromJson(Map<Object?, Object?> json) =>
      PreludeSessionView(
        id: json['id']! as String,
        deviceModel: json['deviceModel']! as String,
        deviceType: PreludeDeviceType.fromWire(
          json['deviceType']! as String,
        ),
        osVersion: json['osVersion']! as String,
        countryCode: json['countryCode']! as String,
        createdAt: _parseTimestamp(json['createdAt'], 'createdAt'),
        lastSeenAt: _parseTimestamp(json['lastSeenAt'], 'lastSeenAt'),
        expiresAt: _parseTimestamp(json['expiresAt'], 'expiresAt'),
      );

  @override
  bool operator ==(Object other) =>
      other is PreludeSessionView &&
      other.id == id &&
      other.deviceModel == deviceModel &&
      other.deviceType == deviceType &&
      other.osVersion == osVersion &&
      other.countryCode == countryCode &&
      other.createdAt == createdAt &&
      other.lastSeenAt == lastSeenAt &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(
    id,
    deviceModel,
    deviceType,
    osVersion,
    countryCode,
    createdAt,
    lastSeenAt,
    expiresAt,
  );

  @override
  String toString() =>
      'PreludeSessionView(id: $id, $deviceType $deviceModel, '
      'os: $osVersion, country: $countryCode, '
      'createdAt: $createdAt, lastSeenAt: $lastSeenAt, '
      'expiresAt: $expiresAt)';
}

/// Pagination knobs for [PreludeSessionClient.listSessions]. Both
/// fields are nullable so the caller can defer to whatever default
/// the server picks — a server-side default change lands without a
/// client release.
class PreludeListSessionsOptions {
  // `assert` would be stripped in release builds; throw explicitly so
  // a programmer error (negative paging) surfaces consistently across
  // build modes — same shape as Android's `require(...)`.
  PreludeListSessionsOptions({this.limit, this.offset}) {
    if (limit != null && limit! < 0) {
      throw ArgumentError.value(limit, 'limit', 'must be >= 0');
    }
    if (offset != null && offset! < 0) {
      throw ArgumentError.value(offset, 'offset', 'must be >= 0');
    }
  }

  final int? limit;
  final int? offset;

  Map<String, Object?> toJson() => {
    if (limit != null) 'limit': limit,
    if (offset != null) 'offset': offset,
  };
}

/// Page of active sessions returned by
/// [PreludeSessionClient.listSessions].
class PreludeListSessionsResponse {
  const PreludeListSessionsResponse({
    required this.sessions,
    required this.total,
    required this.limit,
    required this.offset,
  });

  /// Entries on this page.
  final List<PreludeSessionView> sessions;

  /// Grand total of active sessions; use with [limit] / [offset] to
  /// drive a paginated UI.
  final int total;

  /// Echo of the request's `limit` (or the server default when
  /// absent).
  final int limit;

  /// Echo of the request's `offset` (or `0` when absent).
  final int offset;

  factory PreludeListSessionsResponse.fromJson(
    Map<Object?, Object?> json,
  ) {
    final raw = (json['sessions'] as List?) ?? const [];
    return PreludeListSessionsResponse(
      sessions: [
        for (final s in raw)
          PreludeSessionView.fromJson(Map<Object?, Object?>.from(s as Map)),
      ],
      total: (json['total']! as num).toInt(),
      limit: (json['limit']! as num).toInt(),
      offset: (json['offset']! as num).toInt(),
    );
  }
}

/// Which sessions to revoke on [PreludeSessionClient.revokeSessions].
///
/// Sealed so each case is exhaustive at the call site; the
/// `session` case requires its id at the type level.
sealed class PreludeRevokeTarget {
  const PreludeRevokeTarget();

  /// Every session belonging to this user, across all devices.
  static const PreludeRevokeTarget all = _RevokeAll();

  /// Every session except the one issuing the call.
  static const PreludeRevokeTarget others = _RevokeOthers();

  /// Only the session issuing the call — i.e. this device.
  /// Effectively a [PreludeSessionClient.logout] without rotating
  /// the server-side DPoP-key binding. Other devices stay signed in.
  static const PreludeRevokeTarget mine = _RevokeMine();

  /// A single session by id. The id comes from
  /// [PreludeSessionView.id]. Empty / whitespace-only ids are
  /// rejected up front rather than handed to the server.
  factory PreludeRevokeTarget.session(String sessionID) =
      _RevokeSession;

  Map<String, Object?> toJson();
}

class _RevokeAll extends PreludeRevokeTarget {
  const _RevokeAll();
  @override
  Map<String, Object?> toJson() => const {'kind': 'all'};
  @override
  bool operator ==(Object other) => other is _RevokeAll;
  @override
  int get hashCode => 'all'.hashCode;
  @override
  String toString() => 'PreludeRevokeTarget.all';
}

class _RevokeOthers extends PreludeRevokeTarget {
  const _RevokeOthers();
  @override
  Map<String, Object?> toJson() => const {'kind': 'others'};
  @override
  bool operator ==(Object other) => other is _RevokeOthers;
  @override
  int get hashCode => 'others'.hashCode;
  @override
  String toString() => 'PreludeRevokeTarget.others';
}

class _RevokeMine extends PreludeRevokeTarget {
  const _RevokeMine();
  @override
  Map<String, Object?> toJson() => const {'kind': 'mine'};
  @override
  bool operator ==(Object other) => other is _RevokeMine;
  @override
  int get hashCode => 'mine'.hashCode;
  @override
  String toString() => 'PreludeRevokeTarget.mine';
}

class _RevokeSession extends PreludeRevokeTarget {
  _RevokeSession(this.sessionID) {
    if (sessionID.trim().isEmpty) {
      throw ArgumentError.value(
        sessionID,
        'sessionID',
        'PreludeRevokeTarget.session requires a non-empty id',
      );
    }
  }

  final String sessionID;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'session',
    'sessionID': sessionID,
  };

  @override
  bool operator ==(Object other) =>
      other is _RevokeSession && other.sessionID == sessionID;

  @override
  int get hashCode => Object.hash('session', sessionID);

  @override
  String toString() => 'PreludeRevokeTarget.session($sessionID)';
}

/// Strict ISO 8601 → UTC [DateTime]. Surfaces a malformed timestamp
/// as a structured [ArgumentError] tagged with [field], so a server
/// contract drift on a single field is actionable instead of a silent
/// `null` from [DateTime.tryParse].
DateTime _parseTimestamp(Object? value, String field) {
  if (value is! String) {
    throw ArgumentError.value(
      value,
      field,
      'expected ISO 8601 timestamp string',
    );
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw ArgumentError.value(
      value,
      field,
      'failed to parse `$field` as ISO 8601',
    );
  }
  return parsed.toUtc();
}
