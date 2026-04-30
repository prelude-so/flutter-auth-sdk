import 'redacted_string.dart';

/// Options for [PreludeSessionClient.loginWithPassword].
///
/// The password is wrapped in a [RedactedString] so the struct is
/// safe to `print`, `toString`, or surface in error messages.
/// The constructor still accepts a plain `String` for
/// call-site ergonomics — wrapping happens internally.
class LoginWithPasswordOptions {
  /// Plain-string convenience: wraps [password] in [RedactedString].
  LoginWithPasswordOptions({required this.emailAddress, required String password})
      : password = RedactedString(password);

  /// Pre-wrapped variant — use when the password is already held
  /// in a [RedactedString] further up the call stack.
  const LoginWithPasswordOptions.redacted({
    required this.emailAddress,
    required this.password,
  });

  final String emailAddress;

  /// Held only for the duration of one
  /// [PreludeSessionClient.loginWithPassword] call; never
  /// persisted by the SDK.
  final RedactedString password;

  Map<String, Object?> toJson() => {
    'emailAddress': emailAddress,
    'password': password.value,
  };

  @override
  String toString() =>
      'LoginWithPasswordOptions(emailAddress: $emailAddress, '
      'password: $password)';
}

/// The server's configured password compliancy rules.
///
/// Each numeric field is a minimum count. [maxLength] of `0` means
/// "no upper bound".
class PreludePasswordCompliancy {
  const PreludePasswordCompliancy({
    required this.minLength,
    required this.maxLength,
    required this.uppercase,
    required this.lowercase,
    required this.numbers,
    required this.symbols,
  });

  final int minLength;
  final int maxLength;
  final int uppercase;
  final int lowercase;
  final int numbers;
  final int symbols;

  Map<String, Object?> toJson() => {
    'minLength': minLength,
    'maxLength': maxLength,
    'uppercase': uppercase,
    'lowercase': lowercase,
    'numbers': numbers,
    'symbols': symbols,
  };

  factory PreludePasswordCompliancy.fromJson(Map<Object?, Object?> json) =>
      PreludePasswordCompliancy(
        minLength: (json['minLength']! as num).toInt(),
        maxLength: (json['maxLength']! as num).toInt(),
        uppercase: (json['uppercase']! as num).toInt(),
        lowercase: (json['lowercase']! as num).toInt(),
        numbers: (json['numbers']! as num).toInt(),
        symbols: (json['symbols']! as num).toInt(),
      );

  @override
  bool operator ==(Object other) =>
      other is PreludePasswordCompliancy &&
      other.minLength == minLength &&
      other.maxLength == maxLength &&
      other.uppercase == uppercase &&
      other.lowercase == lowercase &&
      other.numbers == numbers &&
      other.symbols == symbols;

  @override
  int get hashCode =>
      Object.hash(minLength, maxLength, uppercase, lowercase, numbers, symbols);
}

/// Wire-stable identifiers for the rules in
/// [PreludePasswordCompliancy].
enum PreludePasswordCompliancyCriterion {
  minLength('min_length'),
  maxLength('max_length'),
  uppercase('uppercase'),
  lowercase('lowercase'),
  numbers('numbers'),
  symbols('symbols');

  const PreludePasswordCompliancyCriterion(this.wireValue);

  final String wireValue;

  static PreludePasswordCompliancyCriterion fromWire(String wire) {
    for (final v in values) {
      if (v.wireValue == wire) return v;
    }
    throw ArgumentError.value(
      wire,
      'wire',
      'unknown PreludePasswordCompliancyCriterion',
    );
  }
}

/// One rule's outcome when validating a password against the
/// server's compliancy.
class PreludePasswordCompliancyResult {
  const PreludePasswordCompliancyResult({
    required this.criterion,
    required this.actual,
    required this.expected,
    required this.valid,
  });

  final PreludePasswordCompliancyCriterion criterion;

  /// Observed count in the candidate password.
  final int actual;

  /// Required count from the server's configuration.
  final int expected;

  final bool valid;

  Map<String, Object?> toJson() => {
    'criterion': criterion.wireValue,
    'actual': actual,
    'expected': expected,
    'valid': valid,
  };

  factory PreludePasswordCompliancyResult.fromJson(
    Map<Object?, Object?> json,
  ) =>
      PreludePasswordCompliancyResult(
        criterion: PreludePasswordCompliancyCriterion.fromWire(
          json['criterion']! as String,
        ),
        actual: (json['actual']! as num).toInt(),
        expected: (json['expected']! as num).toInt(),
        valid: json['valid']! as bool,
      );

  @override
  bool operator ==(Object other) =>
      other is PreludePasswordCompliancyResult &&
      other.criterion == criterion &&
      other.actual == actual &&
      other.expected == expected &&
      other.valid == valid;

  @override
  int get hashCode => Object.hash(criterion, actual, expected, valid);
}

/// Aggregate outcome of running a password through the server's
/// compliancy.
class PreludePasswordCompliancyResults {
  const PreludePasswordCompliancyResults({
    required this.valid,
    required this.results,
  });

  /// `true` when every result in [results] is valid.
  final bool valid;
  final List<PreludePasswordCompliancyResult> results;

  Map<String, Object?> toJson() => {
    'valid': valid,
    'results': results.map((r) => r.toJson()).toList(growable: false),
  };

  factory PreludePasswordCompliancyResults.fromJson(
    Map<Object?, Object?> json,
  ) {
    final list = (json['results']! as List).cast<Object?>();
    return PreludePasswordCompliancyResults(
      valid: json['valid']! as bool,
      results: list
          .map(
            (e) => PreludePasswordCompliancyResult.fromJson(
              Map<Object?, Object?>.from(e! as Map),
            ),
          )
          .toList(growable: false),
    );
  }
}
