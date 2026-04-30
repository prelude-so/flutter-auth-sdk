/// API endpoint for [PreludeSessionClient].
///
/// - [Endpoint.defaultEndpoint] resolves to the canonical Prelude
///   API address on the native side.
/// - [Endpoint.custom] accepts an explicit URL string — typically
///   the customer's own Prelude session endpoint, or a staging /
///   local-development URL.
sealed class Endpoint {
  const Endpoint();

  /// Canonical Prelude API endpoint. The actual URL is resolved
  /// natively so a Dart-side bump isn't required when iOS / Android
  /// rotate their default address.
  static const Endpoint defaultEndpoint = _DefaultEndpoint();

  /// Explicit URL — used for staging / on-device dev.
  const factory Endpoint.custom(String address) = _CustomEndpoint;

  /// Wire form: `{kind: 'default'}` or
  /// `{kind: 'custom', address: '…'}`. The native plugin unpacks
  /// these into the matching Swift `Endpoint` case.
  Map<String, Object?> toJson();
}

class _DefaultEndpoint extends Endpoint {
  const _DefaultEndpoint();

  @override
  Map<String, Object?> toJson() => const {'kind': 'default'};

  @override
  bool operator ==(Object other) => other is _DefaultEndpoint;

  @override
  int get hashCode => 'default'.hashCode;

  @override
  String toString() => 'Endpoint.default';
}

class _CustomEndpoint extends Endpoint {
  const _CustomEndpoint(this.address);

  final String address;

  @override
  Map<String, Object?> toJson() => {'kind': 'custom', 'address': address};

  @override
  bool operator ==(Object other) =>
      other is _CustomEndpoint && other.address == address;

  @override
  int get hashCode => Object.hash('custom', address);

  @override
  String toString() => 'Endpoint.custom($address)';
}
