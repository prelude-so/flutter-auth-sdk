import 'identifier.dart';

/// Options for [PreludeSessionClient.startOTPLogin].
class StartOTPLoginOptions {
  const StartOTPLoginOptions({required this.identifier, this.loginConfigID});

  /// The phone number or email address to send the OTP to.
  final PreludeIdentifier identifier;

  /// Optional server-side login configuration ID that overrides
  /// the default OTP delivery rules.
  final String? loginConfigID;

  Map<String, Object?> toJson() => {
    'identifier': identifier.toJson(),
    'loginConfigID': loginConfigID,
  };

  @override
  bool operator ==(Object other) =>
      other is StartOTPLoginOptions &&
      other.identifier == identifier &&
      other.loginConfigID == loginConfigID;

  @override
  int get hashCode => Object.hash(identifier, loginConfigID);
}
