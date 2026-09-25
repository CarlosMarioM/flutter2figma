/// A structured, execution-free view of the expressions that build a widget
/// tree.
///
/// The analyzer never runs Dart. It turns constructor calls, literals and
/// references into these values; interpreting what `EdgeInsets.all(16)` means
/// is the compiler's job.
library;

sealed class DartValue {
  const DartValue({this.source});

  /// `relative/path.dart:line` of the expression.
  final String? source;

  Map<String, Object?> toJson();
}

/// `16`, `'Hello'`, `true`, `null`.
class LiteralValue extends DartValue {
  const LiteralValue(this.value, {super.source});

  final Object? value;

  num? get asNum => value is num ? value as num : null;
  double? get asDouble => asNum?.toDouble();
  String? get asString => value is String ? value as String : null;
  bool? get asBool => value is bool ? value as bool : null;

  @override
  Map<String, Object?> toJson() => {'literal': value};
}

/// A constructor call: `Container(...)`, `EdgeInsets.all(16)`.
class ObjectValue extends DartValue {
  ObjectValue({
    required this.type,
    this.constructor,
    this.library,
    this.isWidget = false,
    this.positional = const [],
    this.named = const {},
    this.build,
    super.source,
  });

  /// Class name, e.g. `Container`.
  final String type;

  /// Named constructor, e.g. `all` in `EdgeInsets.all`.
  final String? constructor;

  /// Declaring library URI, e.g. `package:flutter/src/widgets/container.dart`.
  final String? library;

  final bool isWidget;
  final List<DartValue> positional;
  final Map<String, DartValue> named;

  /// For widgets declared in the analyzed project: the tree their `build`
  /// method returns, with constructor arguments substituted for fields.
  final DartValue? build;

  bool get isFlutter => library?.startsWith('package:flutter/') ?? false;

  String get displayName => constructor == null ? type : '$type.$constructor';

  DartValue? operator [](String name) => named[name];

  DartValue? arg(int index) =>
      index < positional.length ? positional[index] : null;

  @override
  Map<String, Object?> toJson() => {
    'new': displayName,
    if (isWidget) 'widget': true,
    if (positional.isNotEmpty)
      'positional': [for (final p in positional) p.toJson()],
    if (named.isNotEmpty)
      'named': {for (final e in named.entries) e.key: e.value.toJson()},
    if (build != null) 'build': build!.toJson(),
  };
}

/// A static reference such as `Colors.blue` or `CrossAxisAlignment.start`.
///
/// When the referenced declaration is a constant whose initializer is
/// available, [constant] holds the analyzed initializer, so
/// `Colors.blue` also carries `MaterialColor(0xFF2196F3, {...})`.
class RefValue extends DartValue {
  const RefValue(this.path, {this.constant, super.source});

  final List<String> path;
  final DartValue? constant;

  String get dotted => path.join('.');
  String get last => path.last;

  @override
  Map<String, Object?> toJson() => {
    'ref': dotted,
    if (constant != null) 'constant': constant!.toJson(),
  };
}

/// Instance property read: `textTheme.bodyLarge`, `color.shade200`.
class AccessValue extends DartValue {
  const AccessValue(this.target, this.name, {super.source});

  final DartValue target;
  final String name;

  @override
  Map<String, Object?> toJson() => {'get': name, 'on': target.toJson()};
}

/// Method call: `Theme.of(context)`, `style.copyWith(...)`.
class CallValue extends DartValue {
  const CallValue(
    this.target,
    this.method, {
    this.positional = const [],
    this.named = const {},
    super.source,
  });

  final DartValue? target;
  final String method;
  final List<DartValue> positional;
  final Map<String, DartValue> named;

  @override
  Map<String, Object?> toJson() => {
    'call': method,
    if (target != null) 'on': target!.toJson(),
    if (positional.isNotEmpty)
      'positional': [for (final p in positional) p.toJson()],
    if (named.isNotEmpty)
      'named': {for (final e in named.entries) e.key: e.value.toJson()},
  };
}

class ListValue extends DartValue {
  const ListValue(this.items, {super.source});

  final List<DartValue> items;

  @override
  Map<String, Object?> toJson() => {
    'list': [for (final i in items) i.toJson()],
  };
}

class MapValue extends DartValue {
  const MapValue(this.entries, {super.source});

  final List<(DartValue, DartValue)> entries;

  DartValue? lookup(Object? key) {
    for (final (k, v) in entries) {
      if (k is LiteralValue && k.value == key) return v;
    }
    return null;
  }

  @override
  Map<String, Object?> toJson() => {
    'map': [
      for (final (k, v) in entries) [k.toJson(), v.toJson()],
    ],
  };
}

/// `cond ? a : b`, or a collection `if`. [otherwise] is null for an `if`
/// without `else`.
class ConditionalValue extends DartValue {
  const ConditionalValue(
    this.condition,
    this.then,
    this.otherwise, {
    super.source,
  });

  final String condition;
  final DartValue then;
  final DartValue? otherwise;

  @override
  Map<String, Object?> toJson() => {
    'if': condition,
    'then': then.toJson(),
    if (otherwise != null) 'else': otherwise!.toJson(),
  };
}

/// A closure. [returns] is its result expression when it has a single one
/// (useful for `itemBuilder`-style callbacks).
class FunctionValue extends DartValue {
  const FunctionValue({this.returns, super.source});

  final DartValue? returns;

  @override
  Map<String, Object?> toJson() => {
    'function': true,
    if (returns != null) 'returns': returns!.toJson(),
  };
}

/// Anything the analyzer can't represent statically.
class UnknownValue extends DartValue {
  const UnknownValue(this.code, {super.source});

  /// The original source text.
  final String code;

  @override
  Map<String, Object?> toJson() => {'unknown': code};
}
