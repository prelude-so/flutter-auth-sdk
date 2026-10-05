/// Types backing the passkey (WebAuthn) methods on
/// [PreludeAuthClient].
library;

import 'package:flutter/foundation.dart';

/// Options for [PreludeAuthClient.registerPasskey].
class RegisterPasskeyOptions {
  const RegisterPasskeyOptions({
    required this.username,
    this.displayName,
    this.nickname,
  });

  /// Account label the authenticator shows in its UI — typically the
  /// user's email address or phone number.
  final String username;

  /// Friendlier name shown alongside [username]. Defaults to
  /// [username] server-side when `null`.
  final String? displayName;

  /// Server-side label for the credential (`"iPhone"`, `"Pixel"`),
  /// returned by [PreludeAuthClient.listPasskeys].
  final String? nickname;

  Map<String, Object?> toJson() => {
    'username': username,
    'displayName': displayName,
    'nickname': nickname,
  };
}

/// Options for [PreludeAuthClient.loginWithPasskey].
class PasskeyLoginOptions {
  const PasskeyLoginOptions({this.autofill = false});

  /// Offer credentials through the keyboard's AutoFill row instead
  /// of a modal sheet. iOS only; ignored on Android. Defaults to
  /// `false`.
  final bool autofill;

  Map<String, Object?> toJson() => {'autofill': autofill};
}

/// One passkey registered against the signed-in user.
class PreludePasskeyCredential {
  const PreludePasskeyCredential({
    required this.credentialID,
    required this.nickname,
    required this.transports,
    required this.backupState,
    required this.createdAt,
    required this.lastUsedAt,
  });

  /// Server-side identifier; pass to
  /// [PreludeAuthClient.renamePasskey] or
  /// [PreludeAuthClient.deletePasskey].
  final String credentialID;

  /// Label set at registration or via
  /// [PreludeAuthClient.renamePasskey]; `null` when unset.
  final String? nickname;

  /// Transports the authenticator reported (`"internal"`,
  /// `"hybrid"`, …).
  final List<String> transports;

  /// `true` when the credential is synced to the platform's
  /// keychain, so it survives losing this device.
  final bool backupState;

  /// When the credential was registered.
  final DateTime createdAt;

  /// Last successful assertion. Equals [createdAt] until first use.
  final DateTime lastUsedAt;

  factory PreludePasskeyCredential.fromJson(Map<Object?, Object?> json) =>
      PreludePasskeyCredential(
        credentialID: json['credentialID']! as String,
        nickname: json['nickname'] as String?,
        transports: List<String>.unmodifiable(
          (json['transports'] as List<Object?>? ?? const [])
              .whereType<String>(),
        ),
        backupState: json['backupState']! as bool,
        createdAt: _fromUnixSeconds(json['createdAt'], 'createdAt'),
        lastUsedAt: _fromUnixSeconds(json['lastUsedAt'], 'lastUsedAt'),
      );

  @override
  bool operator ==(Object other) =>
      other is PreludePasskeyCredential &&
      other.credentialID == credentialID &&
      other.nickname == nickname &&
      listEquals(other.transports, transports) &&
      other.backupState == backupState &&
      other.createdAt == createdAt &&
      other.lastUsedAt == lastUsedAt;

  @override
  int get hashCode => Object.hash(
    credentialID,
    nickname,
    Object.hashAll(transports),
    backupState,
    createdAt,
    lastUsedAt,
  );

  @override
  String toString() =>
      'PreludePasskeyCredential($credentialID, nickname: $nickname)';
}

/// Outcome of [PreludeAuthClient.registerPasskey].
class PasskeyRegistrationResult {
  const PasskeyRegistrationResult({
    required this.credential,
    required this.alreadyRegistered,
  });

  final PreludePasskeyCredential credential;

  /// `true` when the server already held this credential, so the
  /// ceremony changed nothing — registration is idempotent.
  final bool alreadyRegistered;

  factory PasskeyRegistrationResult.fromJson(Map<Object?, Object?> json) =>
      PasskeyRegistrationResult(
        credential: PreludePasskeyCredential.fromJson(
          Map<Object?, Object?>.from(json['credential']! as Map),
        ),
        alreadyRegistered: json['alreadyRegistered']! as bool,
      );

  @override
  bool operator ==(Object other) =>
      other is PasskeyRegistrationResult &&
      other.credential == credential &&
      other.alreadyRegistered == alreadyRegistered;

  @override
  int get hashCode => Object.hash(credential, alreadyRegistered);

  @override
  String toString() =>
      'PasskeyRegistrationResult($credential, '
      'alreadyRegistered: $alreadyRegistered)';
}

/// Unix seconds on the wire, [DateTime] in Dart — both native
/// plugins encode passkey timestamps as integers.
DateTime _fromUnixSeconds(Object? raw, String field) {
  if (raw is int) {
    return DateTime.fromMillisecondsSinceEpoch(raw * 1000, isUtc: true);
  }
  throw ArgumentError.value(raw, field, 'expected unix seconds');
}
