/// A `String` wrapper whose textual representation is `<redacted>`.
///
/// Use for secrets that must not appear in logs, errors, `print`,
/// or `toString` output. Callers reach the raw value through
/// [value] — an explicit, named unwrap, so unintentional logging
/// of the underlying secret is eye-catching at the call site.
///
/// Two redacted strings with the same underlying [value] compare
/// equal. The hash uses [value] so wrapping does not change
/// hashing behaviour for collections.
class RedactedString {
  const RedactedString(this.value);

  /// The unwrapped secret. Reach for it explicitly when (and only
  /// when) you intend to expose the value — typically just inside
  /// the SDK before serialising onto the platform channel.
  final String value;

  @override
  String toString() => '<redacted>';

  @override
  bool operator ==(Object other) =>
      other is RedactedString && other.value == value;

  @override
  int get hashCode => value.hashCode;
}
