/// A JSON value as carried by the JWT claims surfaced through
/// [PreludeProfile.extras]. Int and double cases are kept distinct
/// so 64-bit integer claims (e.g. large user IDs) survive the
/// bridge without rounding through `Double`.
sealed class PreludeJSONValue {
  const PreludeJSONValue();

  const factory PreludeJSONValue.string(String value) = PreludeJSONString;
  const factory PreludeJSONValue.integer(int value) = PreludeJSONInt;
  const factory PreludeJSONValue.double_(double value) = PreludeJSONDouble;
  const factory PreludeJSONValue.boolean(bool value) = PreludeJSONBool;
  const factory PreludeJSONValue.array(List<PreludeJSONValue> values) =
      PreludeJSONArray;
  const factory PreludeJSONValue.object(Map<String, PreludeJSONValue> values) =
      PreludeJSONObject;
  const factory PreludeJSONValue.null_() = PreludeJSONNull;

  /// Decode a tagged-map value off the platform channel. The
  /// wire shape is:
  /// `{kind: 'string'|'int'|'double'|'bool'|'array'|'object'|'null', value: …}`.
  factory PreludeJSONValue.fromJson(Object? raw) {
    if (raw is! Map) {
      throw ArgumentError.value(raw, 'raw', 'expected a tagged map');
    }
    final json = Map<Object?, Object?>.from(raw);
    final kind = json['kind'];
    switch (kind) {
      case 'string':
        return PreludeJSONValue.string(json['value']! as String);
      case 'int':
        // Method-channel ints come over as `int` in Dart already.
        return PreludeJSONValue.integer((json['value']! as num).toInt());
      case 'double':
        return PreludeJSONValue.double_((json['value']! as num).toDouble());
      case 'bool':
        return PreludeJSONValue.boolean(json['value']! as bool);
      case 'array':
        final list = (json['value']! as List).cast<Object?>();
        return PreludeJSONValue.array(
          list.map(PreludeJSONValue.fromJson).toList(growable: false),
        );
      case 'object':
        final map = Map<Object?, Object?>.from(json['value']! as Map);
        return PreludeJSONValue.object({
          for (final e in map.entries)
            e.key! as String: PreludeJSONValue.fromJson(e.value),
        });
      case 'null':
        return const PreludeJSONValue.null_();
    }
    throw ArgumentError.value(kind, 'kind', 'unknown PreludeJSONValue tag');
  }

  /// Inverse of [fromJson].
  Map<String, Object?> toJson();

  /// Strip the tagging and return a plain Dart value
  /// (`String`, `int`, `double`, `bool`, `List`, `Map`, or `null`).
  /// Useful when forwarding extras into UI code that doesn't care
  /// about the JWT's int/double distinction.
  Object? toPlain();
}

class PreludeJSONString extends PreludeJSONValue {
  const PreludeJSONString(this.value);
  final String value;
  @override
  Map<String, Object?> toJson() => {'kind': 'string', 'value': value};
  @override
  Object? toPlain() => value;
  @override
  bool operator ==(Object other) =>
      other is PreludeJSONString && other.value == value;
  @override
  int get hashCode => Object.hash('string', value);
}

class PreludeJSONInt extends PreludeJSONValue {
  const PreludeJSONInt(this.value);
  final int value;
  @override
  Map<String, Object?> toJson() => {'kind': 'int', 'value': value};
  @override
  Object? toPlain() => value;
  @override
  bool operator ==(Object other) =>
      other is PreludeJSONInt && other.value == value;
  @override
  int get hashCode => Object.hash('int', value);
}

class PreludeJSONDouble extends PreludeJSONValue {
  const PreludeJSONDouble(this.value);
  final double value;
  @override
  Map<String, Object?> toJson() => {'kind': 'double', 'value': value};
  @override
  Object? toPlain() => value;
  @override
  bool operator ==(Object other) =>
      other is PreludeJSONDouble && other.value == value;
  @override
  int get hashCode => Object.hash('double', value);
}

class PreludeJSONBool extends PreludeJSONValue {
  const PreludeJSONBool(this.value);
  final bool value;
  @override
  Map<String, Object?> toJson() => {'kind': 'bool', 'value': value};
  @override
  Object? toPlain() => value;
  @override
  bool operator ==(Object other) =>
      other is PreludeJSONBool && other.value == value;
  @override
  int get hashCode => Object.hash('bool', value);
}

class PreludeJSONArray extends PreludeJSONValue {
  const PreludeJSONArray(this.values);
  final List<PreludeJSONValue> values;
  @override
  Map<String, Object?> toJson() => {
    'kind': 'array',
    'value': values.map((v) => v.toJson()).toList(growable: false),
  };
  @override
  Object? toPlain() => values.map((v) => v.toPlain()).toList(growable: false);
  @override
  bool operator ==(Object other) {
    if (other is! PreludeJSONArray) return false;
    if (other.values.length != values.length) return false;
    for (var i = 0; i < values.length; i++) {
      if (other.values[i] != values[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(['array', ...values]);
}

class PreludeJSONObject extends PreludeJSONValue {
  const PreludeJSONObject(this.values);
  final Map<String, PreludeJSONValue> values;
  @override
  Map<String, Object?> toJson() => {
    'kind': 'object',
    'value': {for (final e in values.entries) e.key: e.value.toJson()},
  };
  @override
  Object? toPlain() => {
    for (final e in values.entries) e.key: e.value.toPlain(),
  };
  @override
  bool operator ==(Object other) {
    if (other is! PreludeJSONObject) return false;
    if (other.values.length != values.length) return false;
    for (final e in values.entries) {
      if (other.values[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered([
    'object',
    ...values.entries.map((e) => Object.hash(e.key, e.value)),
  ]);
}

class PreludeJSONNull extends PreludeJSONValue {
  const PreludeJSONNull();
  @override
  Map<String, Object?> toJson() => const {'kind': 'null'};
  @override
  Object? toPlain() => null;
  @override
  bool operator ==(Object other) => other is PreludeJSONNull;
  @override
  int get hashCode => 'null'.hashCode;
}
