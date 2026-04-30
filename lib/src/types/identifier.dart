/// Identifier kind used to start a login flow.
enum PreludeIdentifierType {
  phoneNumber('phone_number'),
  emailAddress('email_address');

  const PreludeIdentifierType(this.wireValue);

  /// Wire string used by the Prelude API.
  final String wireValue;

  static PreludeIdentifierType fromWire(String wire) {
    for (final v in values) {
      if (v.wireValue == wire) return v;
    }
    throw ArgumentError.value(wire, 'wire', 'unknown PreludeIdentifierType');
  }
}

/// A user identifier (phone number or email address).
class PreludeIdentifier {
  const PreludeIdentifier({required this.type, required this.value});

  /// Convenience: phone-number identifier.
  PreludeIdentifier.phoneNumber(String value)
    : this(type: PreludeIdentifierType.phoneNumber, value: value);

  /// Convenience: email-address identifier.
  PreludeIdentifier.emailAddress(String value)
    : this(type: PreludeIdentifierType.emailAddress, value: value);

  final PreludeIdentifierType type;
  final String value;

  Map<String, Object?> toJson() => {'type': type.wireValue, 'value': value};

  factory PreludeIdentifier.fromJson(Map<Object?, Object?> json) =>
      PreludeIdentifier(
        type: PreludeIdentifierType.fromWire(json['type']! as String),
        value: json['value']! as String,
      );

  @override
  bool operator ==(Object other) =>
      other is PreludeIdentifier && other.type == type && other.value == value;

  @override
  int get hashCode => Object.hash(type, value);

  @override
  String toString() => 'PreludeIdentifier($type, $value)';
}
