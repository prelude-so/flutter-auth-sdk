/// Status of a step-up flow as reported by the server.
enum StepUpStatus {
  /// Challenge issued; complete it (typically via
  /// [PreludeSessionClient.submitStepUpOTP]) to be granted the
  /// scope.
  continueStep('continue'),

  /// Server is reviewing the request asynchronously. The caller
  /// has nothing to do; poll or surface UI as needed.
  underReview('review'),

  /// Server refused to grant the scope.
  blocked('block');

  const StepUpStatus(this.wireValue);

  final String wireValue;

  static StepUpStatus fromWire(String wire) {
    for (final v in values) {
      if (v.wireValue == wire) return v;
    }
    throw ArgumentError.value(wire, 'wire', 'unknown StepUpStatus');
  }
}

/// Handle returned by [PreludeSessionClient.requestStepUp] and
/// [PreludeSessionClient.submitStepUpOTP].
///
/// The challenge token + expiry stay on the native side, keyed by
/// [challengeID] in a per-client cache. Only [challengeID] travels
/// over the channel when the consumer hands the challenge back to
/// [PreludeSessionClient.submitStepUpOTP] — the bridge looks up
/// the cached token, so a Dart-side log or debugger can never
/// observe the bearer credential.
///
/// Consumers receive a [StepUpChallenge] from the SDK and pass it
/// back unchanged. The constructor is library-private; instances
/// can't be forged from Dart.
class StepUpChallenge {
  const StepUpChallenge._({
    required this.status,
    required this.challengeID,
    required this.currentStep,
    required this.requestedScope,
  });

  final StepUpStatus status;

  /// Server-side identifier for this challenge attempt. Stable
  /// across the lifetime of one challenge step; rotates on each
  /// successful [PreludeSessionClient.submitStepUpOTP] that
  /// advances the flow.
  final String challengeID;

  /// Next server step (`verify_email`, `verify_sms`, `completed`,
  /// …). `null` for a blocked challenge.
  final String? currentStep;

  /// Scope passed to [PreludeSessionClient.requestStepUp].
  final String requestedScope;

  /// Wire form sent across the platform channel. Carries no
  /// secret material — the native plugin maps [challengeID] back
  /// to the cached challenge token on submit.
  Map<String, Object?> toJson() => {
    'status': status.wireValue,
    'challengeID': challengeID,
    'currentStep': currentStep,
    'requestedScope': requestedScope,
  };

  factory StepUpChallenge.fromJson(Map<Object?, Object?> json) =>
      StepUpChallenge._(
        status: StepUpStatus.fromWire(json['status']! as String),
        challengeID: json['challengeID']! as String,
        currentStep: json['currentStep'] as String?,
        requestedScope: json['requestedScope']! as String,
      );

  @override
  String toString() =>
      'StepUpChallenge($status, challengeID: $challengeID, '
      'currentStep: $currentStep, scope: $requestedScope)';
}
