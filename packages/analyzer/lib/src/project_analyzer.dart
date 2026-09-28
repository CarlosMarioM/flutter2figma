import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:path/path.dart' as p;

import 'values.dart';

/// Result of statically analyzing a Flutter project.
class ProjectAnalysis {
  ProjectAnalysis({
    required this.name,
    required this.root,
    required this.files,
    required this.widgets,
    required this.diagnostics,
  });

  /// Package name from `pubspec.yaml`.
  final String name;
  final String root;

  /// Analyzed `.dart` files, relative to [root].
  final List<String> files;

  /// Every widget class declared in the project.
  final List<WidgetClass> widgets;

  final List<String> diagnostics;

  /// Widget classes whose `build` produces a `Scaffold`.
  List<WidgetClass> get screens => [
    for (final w in widgets)
      if (w.isScreen) w,
  ];
}

/// A `StatelessWidget` / `StatefulWidget` subclass declared in the project.
class WidgetClass {
  WidgetClass({required this.name, required this.source, required this.tree});

  final String name;
  final String source;

  /// What `build` returns, analyzed with no constructor arguments bound.
  final DartValue? tree;

  bool get isScreen {
    final t = tree;
    return t is ObjectValue && t.isFlutter && t.type == 'Scaffold';
  }
}

/// Resolves every library under `lib/` and extracts widget construction trees.
class FlutterProjectAnalyzer {
  FlutterProjectAnalyzer(String root) : root = p.normalize(p.absolute(root));

  final String root;

  Future<ProjectAnalysis> analyze() async {
    final diagnostics = <String>[];
    final libDir = p.join(root, 'lib');
    if (!Directory(libDir).existsSync()) {
      throw ArgumentError('No lib/ directory in $root');
    }
    if (!File(p.join(root, '.dart_tool', 'package_config.json')).existsSync()) {
      throw StateError(
        'Missing .dart_tool/package_config.json in $root. Run `flutter pub get` first.',
      );
    }

    final files =
        Directory(libDir)
            .listSync(recursive: true)
            .whereType<File>()
            .map((f) => f.path)
            .where((f) => f.endsWith('.dart'))
            .toList()
          ..sort();

    final collection = AnalysisContextCollection(includedPaths: [libDir]);
    final units = <ResolvedUnitResult>[];
    for (final file in files) {
      final session = collection.contextFor(file).currentSession;
      final result = await session.getResolvedUnit(file);
      if (result is! ResolvedUnitResult) {
        diagnostics.add('Could not resolve ${p.relative(file, from: root)}');
        continue;
      }
      units.add(result);
      for (final d in result.diagnostics) {
        if (d.severity == Severity.error) {
          final line = result.lineInfo.getLocation(d.offset).lineNumber;
          diagnostics.add(
            'Dart error in ${p.relative(file, from: root)}:$line: ${d.message}',
          );
        }
      }
    }

    final index = <String, ClassDeclaration>{};
    final declarations = <String, AstNode>{};
    void declare(Element? element, AstNode node) {
      final key = _declKey(element);
      if (key != null) declarations[key] = node;
    }

    for (final unit in units) {
      for (final decl in unit.unit.declarations) {
        switch (decl) {
          case ClassDeclaration():
            final element = decl.declaredFragment?.element;
            if (element != null) index[_key(element)] = decl;
            for (final member in decl.body.members) {
              switch (member) {
                case FieldDeclaration():
                  for (final v in member.fields.variables) {
                    declare(v.declaredFragment?.element, v);
                  }
                case MethodDeclaration():
                  declare(member.declaredFragment?.element, member);
                default:
                  break;
              }
            }
          case TopLevelVariableDeclaration():
            for (final v in decl.variables.variables) {
              declare(v.declaredFragment?.element, v);
            }
          case FunctionDeclaration():
            declare(decl.declaredFragment?.element, decl);
          default:
            break;
        }
      }
    }

    final expander = _Expander(root, index, declarations);
    final widgets = <WidgetClass>[];
    for (final decl in index.values) {
      final element = decl.declaredFragment!.element;
      if (!_isWidgetClass(element)) continue;
      widgets.add(
        WidgetClass(
          name: element.name ?? decl.namePart.typeName.lexeme,
          source: expander.location(
            decl,
            offset: decl.namePart.typeName.offset,
          )!,
          tree: expander.expandClass(decl, const {}, const {}),
        ),
      );
    }

    return ProjectAnalysis(
      name: _pubspecName() ?? p.basename(root),
      root: root,
      files: [for (final f in files) p.relative(f, from: root)],
      widgets: widgets,
      diagnostics: diagnostics,
    );
  }

  String? _pubspecName() {
    final pubspec = File(p.join(root, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return null;
    final match = RegExp(
      r'^name:\s*([\w]+)',
      multiLine: true,
    ).firstMatch(pubspec.readAsStringSync());
    return match?.group(1);
  }
}

const _frameworkUri = 'package:flutter/src/widgets/framework.dart';

String _key(InterfaceElement e) => '${e.library.uri}#${e.name}';

/// Identity for top-level and member declarations. Implicit getters of
/// fields/variables map to the variable itself.
String? _declKey(Element? element) {
  var e = element;
  if (e is PropertyAccessorElement && e.isOriginVariable) e = e.variable;
  if (e == null || e.name == null) return null;
  final enclosing = e.enclosingElement;
  final owner = enclosing is InterfaceElement ? enclosing.name : '';
  return '${e.library?.uri}#$owner.${e.name}';
}

/// Whether [element] belongs to an instance rather than a class or library.
bool _isInstanceMember(Element? element) {
  var e = element;
  if (e is PropertyAccessorElement && e.isOriginVariable) e = e.variable;
  if (e?.enclosingElement is! InterfaceElement) return false;
  return switch (e) {
    VariableElement(:final isStatic) => !isStatic,
    ExecutableElement(:final isStatic) => !isStatic,
    _ => false,
  };
}

bool _isFlutterClass(InterfaceType t, String name) =>
    t.element.name == name && t.element.library.uri.toString() == _frameworkUri;

bool _isWidgetClass(InterfaceElement e) => e.allSupertypes.any(
  (t) =>
      _isFlutterClass(t, 'StatelessWidget') ||
      _isFlutterClass(t, 'StatefulWidget'),
);

bool _isWidgetType(DartType? type) {
  if (type is! InterfaceType) return false;
  return _isFlutterClass(type, 'Widget') ||
      type.element.allSupertypes.any((t) => _isFlutterClass(t, 'Widget'));
}

/// Analysis state for one widget expansion.
class _Scope {
  const _Scope({
    required this.bindings,
    required this.locals,
    required this.owners,
    required this.expanding,
    required this.depth,
    this.params = const {},
  });

  /// A scope for a declaration outside any widget: no fields, no locals.
  _Scope.detached({
    required this.locals,
    required this.expanding,
    required this.depth,
    this.params = const {},
  }) : bindings = const {},
       owners = const {};

  _Scope copyWith({
    Map<String, Expression>? locals,
    Map<String, DartValue>? params,
    Set<String>? expanding,
    int? depth,
  }) => _Scope(
    bindings: bindings,
    locals: locals ?? this.locals,
    owners: owners,
    expanding: expanding ?? this.expanding,
    depth: depth ?? this.depth,
    params: params ?? this.params,
  );

  /// Constructor arguments of the widget being expanded, by field name.
  final Map<String, DartValue> bindings;

  /// Local variable initializers in the enclosing `build`.
  final Map<String, Expression> locals;

  /// Names of the widget class (and its `State`) being expanded.
  final Set<String> owners;

  /// Project classes currently being expanded, to stop recursion.
  final Set<String> expanding;

  final int depth;

  /// Arguments bound to the parameters of a project function being inlined.
  final Map<String, DartValue> params;
}

class _Expander {
  _Expander(this.root, this.index, this.declarations);

  static const _maxDepth = 16;
  static const _maxConstDepth = 8;

  final String root;
  final Map<String, ClassDeclaration> index;

  /// Project variables, getters, functions and methods by [_declKey].
  final Map<String, AstNode> declarations;
  final _constCache = <Element, DartValue?>{};
  final _staticCache = <String, DartValue?>{};

  String? location(AstNode node, {int? offset}) {
    final unit = node.root;
    if (unit is! CompilationUnit) return null;
    final path = unit.declaredFragment?.source.fullName;
    if (path == null || !p.isWithin(root, path)) return null;
    final line = unit.lineInfo.getLocation(offset ?? node.offset).lineNumber;
    return '${p.relative(path, from: root)}:$line';
  }

  /// Returns what [decl]'s `build` evaluates to.
  DartValue? expandClass(
    ClassDeclaration decl,
    Map<String, DartValue> bindings,
    Set<String> expanding, {
    int depth = 0,
  }) {
    final element = decl.declaredFragment!.element;
    final key = _key(element);
    final owners = {element.name!};
    var buildOwner = decl;

    final isStateful = element.allSupertypes.any(
      (t) => _isFlutterClass(t, 'StatefulWidget'),
    );
    if (isStateful) {
      final created = _returnExpression(_method(decl, 'createState'));
      final stateElement = created is InstanceCreationExpression
          ? created.constructorName.type.element
          : null;
      final stateDecl = stateElement is InterfaceElement
          ? index[_key(stateElement)]
          : null;
      if (stateDecl == null) return null;
      buildOwner = stateDecl;
      owners.add(stateElement!.name!);
    }

    final build = _method(buildOwner, 'build');
    final result = _returnExpression(build);
    if (result == null) return null;

    return value(
      result,
      _Scope(
        bindings: bindings,
        locals: _locals(build!),
        owners: owners,
        expanding: {...expanding, key},
        depth: depth,
      ),
    );
  }

  MethodDeclaration? _method(ClassDeclaration decl, String name) {
    for (final m in decl.body.members.whereType<MethodDeclaration>()) {
      if (m.name.lexeme == name) return m;
    }
    return null;
  }

  Expression? _returnExpression(MethodDeclaration? method) =>
      _bodyReturn(method?.body);

  /// The expression a function body returns: its `=>` expression, or the
  /// last top-level `return`.
  Expression? _bodyReturn(FunctionBody? body) {
    if (body is ExpressionFunctionBody) return body.expression;
    if (body is BlockFunctionBody) {
      for (final s in body.block.statements.reversed) {
        if (s is ReturnStatement) return s.expression;
      }
    }
    return null;
  }

  Map<String, Expression> _locals(AstNode body) {
    final collector = _LocalsCollector();
    body.accept(collector);
    return collector.locals;
  }

  DartValue value(Expression e, _Scope s) {
    final loc = location(e);
    switch (e) {
      case IntegerLiteral():
        return LiteralValue(e.value, source: loc);
      case DoubleLiteral():
        return LiteralValue(e.value, source: loc);
      case BooleanLiteral():
        return LiteralValue(e.value, source: loc);
      case NullLiteral():
        return LiteralValue(null, source: loc);
      case SimpleStringLiteral():
        return LiteralValue(e.value, source: loc);
      case AdjacentStrings():
        final parts = [for (final s2 in e.strings) value(s2, s)];
        return LiteralValue(parts.map(_stringOf).join(), source: loc);
      case StringInterpolation():
        final buffer = StringBuffer();
        for (final element in e.elements) {
          switch (element) {
            case InterpolationString():
              buffer.write(element.value);
            case InterpolationExpression():
              buffer.write(_stringOf(value(element.expression, s)));
          }
        }
        return LiteralValue(buffer.toString(), source: loc);
      case PrefixExpression(operator: Token(lexeme: '-')):
        final inner = value(e.operand, s);
        if (inner is LiteralValue && inner.value is num) {
          return LiteralValue(-(inner.value as num), source: loc);
        }
        return UnknownValue(e.toSource(), source: loc);
      case ParenthesizedExpression():
        return value(e.expression, s);
      case AsExpression():
        return value(e.expression, s);
      case PostfixExpression(operator: Token(lexeme: '!')):
        return value(e.operand, s);
      case InstanceCreationExpression():
        return _object(e, s, loc);
      case MethodInvocation():
        final target = e.target;
        final positional = _positional(e.argumentList, s);
        final named = _named(e.argumentList, s);
        return CallValue(
          target == null ? null : value(target, s),
          e.methodName.name,
          positional: positional,
          named: named,
          result: target == null || target is ThisExpression || _isStatic(e)
              ? _invoke(e.methodName.element, positional, named, s)
              : null,
          source: loc,
        );
      case PrefixedIdentifier():
        return _prefixed(e, s, loc);
      case PropertyAccess():
        final target = e.target;
        final name = e.propertyName.name;
        if (target is ThisExpression) {
          return _member(e.propertyName, s, loc);
        }
        if (target == null) return UnknownValue(e.toSource(), source: loc);
        return AccessValue(value(target, s), name, source: loc);
      case SimpleIdentifier():
        return _identifier(e, s, loc);
      case ConditionalExpression():
        return ConditionalValue(
          e.condition.toSource(),
          value(e.thenExpression, s),
          value(e.elseExpression, s),
          source: loc,
        );
      case FunctionExpression():
        final body = e.body;
        Expression? returned;
        if (body is ExpressionFunctionBody) {
          returned = body.expression;
        } else if (body is BlockFunctionBody) {
          final returns = body.block.statements
              .whereType<ReturnStatement>()
              .toList();
          if (returns.length == 1) returned = returns.single.expression;
        }
        return FunctionValue(
          returns: returned == null ? null : value(returned, s),
          source: loc,
        );
      case ListLiteral():
        return ListValue(_collection(e.elements, s), source: loc);
      case SetOrMapLiteral():
        if (e.isMap) {
          return MapValue([
            for (final entry in e.elements.whereType<MapLiteralEntry>())
              (value(entry.key, s), value(entry.value, s)),
          ], source: loc);
        }
        return ListValue(_collection(e.elements, s), source: loc);
      default:
        return UnknownValue(e.toSource(), source: loc);
    }
  }

  String _stringOf(DartValue v) => switch (v) {
    LiteralValue(value: final Object value) => '$value',
    UnknownValue(:final code) => '{$code}',
    AccessValue(:final name) => '{$name}',
    RefValue(:final last) => '{$last}',
    _ => '{…}',
  };

  List<DartValue> _collection(List<CollectionElement> elements, _Scope s) {
    final out = <DartValue>[];
    for (final element in elements) {
      switch (element) {
        case Expression():
          out.add(value(element, s));
        case IfElement():
          final then = _collection([element.thenElement], s);
          final otherwise = element.elseElement == null
              ? null
              : _collection([element.elseElement!], s);
          if (then.length == 1) {
            out.add(
              ConditionalValue(
                element.expression.toSource(),
                then.single,
                otherwise?.singleOrNull,
                source: location(element),
              ),
            );
          }
        case SpreadElement():
          final spread = value(element.expression, s);
          if (spread is ListValue) {
            out.addAll(spread.items);
          } else {
            out.add(spread);
          }
        default:
          out.add(UnknownValue(element.toSource(), source: location(element)));
      }
    }
    return out;
  }

  List<DartValue> _positional(ArgumentList args, _Scope s) => [
    for (final a in args.arguments)
      if (a is! NamedArgument) value(a.argumentExpression, s),
  ];

  Map<String, DartValue> _named(ArgumentList args, _Scope s) => {
    for (final a in args.arguments.whereType<NamedArgument>())
      a.name.lexeme: value(a.argumentExpression, s),
  };

  DartValue _object(InstanceCreationExpression e, _Scope s, String? loc) {
    final classElement = e.constructorName.type.element;
    final positional = _positional(e.argumentList, s);
    final named = _named(e.argumentList, s);
    final isWidget = _isWidgetType(e.staticType);

    DartValue? build;
    if (isWidget && classElement is InterfaceElement) {
      final key = _key(classElement);
      final decl = index[key];
      if (decl != null && !s.expanding.contains(key) && s.depth < _maxDepth) {
        final bindings = <String, DartValue>{...named};
        final params = e.constructorName.element?.formalParameters ?? const [];
        final positionalParams = params.where((p) => p.isPositional).toList();
        for (
          var i = 0;
          i < positional.length && i < positionalParams.length;
          i++
        ) {
          bindings[positionalParams[i].name!] = positional[i];
        }
        build = expandClass(decl, bindings, s.expanding, depth: s.depth + 1);
      }
    }

    return ObjectValue(
      type: e.constructorName.type.name.lexeme,
      constructor: e.constructorName.name?.name,
      library: classElement?.library?.uri.toString(),
      isWidget: isWidget,
      positional: positional,
      named: named,
      build: build,
      source: loc,
    );
  }

  DartValue _prefixed(PrefixedIdentifier e, _Scope s, String? loc) {
    final prefixElement = e.prefix.element;
    final name = e.identifier.name;

    if (prefixElement is PrefixElement) {
      // `m.Colors` style import prefix: drop it.
      return _identifier(e.identifier, s, loc);
    }
    if (prefixElement is InterfaceElement) {
      return RefValue(
        [e.prefix.name, name],
        resolved: _resolve(e.element, s),
        inProject: _inProject(e.element),
        source: loc,
      );
    }
    if (e.prefix.name == 'widget' && s.bindings.containsKey(name)) {
      return s.bindings[name]!;
    }
    return AccessValue(
      _identifier(e.prefix, s, location(e.prefix)),
      name,
      source: loc,
    );
  }

  DartValue _identifier(SimpleIdentifier e, _Scope s, String? loc) {
    final name = e.name;
    final element = e.element;

    if (element is LocalVariableElement) {
      final init = s.locals[name];
      if (init != null) {
        // Guard against `final a = a;` style self references.
        return value(init, s.copyWith(locals: {...s.locals}..remove(name)));
      }
      return UnknownValue(name, source: loc);
    }
    if (element is FormalParameterElement) {
      return s.params[name] ?? UnknownValue(name, source: loc);
    }
    if (element is InterfaceElement) {
      return RefValue([name], source: loc);
    }
    if (_isInstanceMember(element)) return _member(e, s, loc);
    final resolved = _resolve(element, s);
    if (resolved != null) {
      // A static member referenced from inside its class: keep the class
      // name so the reference reads like it does from outside.
      final enclosing = element?.enclosingElement;
      return RefValue(
        [if (enclosing is InterfaceElement) enclosing.name!, name],
        resolved: resolved,
        inProject: _inProject(element),
        source: loc,
      );
    }
    return UnknownValue(name, source: loc);
  }

  /// A field or getter of the widget (or `State`) being expanded: the bound
  /// constructor argument, else its initializer / getter body.
  DartValue _member(SimpleIdentifier e, _Scope s, String? loc) {
    final name = e.name;
    final owner = e.element?.enclosingElement?.name;
    if (owner == null || !s.owners.contains(owner)) {
      return UnknownValue(name, source: loc);
    }
    return s.bindings[name] ??
        _declared(e.element, s, instance: true) ??
        UnknownValue(name, source: loc);
  }

  bool _inProject(Element? element) {
    final path = element?.library?.firstFragment.source.fullName;
    return path != null && p.isWithin(root, path);
  }

  bool _isStatic(MethodInvocation e) {
    final element = e.methodName.element;
    return element is ExecutableElement && element.isStatic;
  }

  /// Value of a non-instance declaration: any `const` (SDK included), or a
  /// project variable / getter.
  DartValue? _resolve(Element? element, _Scope s) =>
      _constantOf(element, s.depth) ?? _declared(element, s, instance: false);

  /// Analyzes a project variable initializer or getter body.
  ///
  /// Static and top-level results don't depend on the call site and are
  /// cached; instance members are analyzed in the widget's scope.
  DartValue? _declared(Element? element, _Scope s, {required bool instance}) {
    final key = _declKey(element);
    final decl = key == null ? null : declarations[key];
    if (decl == null || s.expanding.contains(key) || s.depth >= _maxDepth) {
      return null;
    }
    if (!instance && _staticCache.containsKey(key)) return _staticCache[key];

    final (Expression? expr, AstNode? body) = switch (decl) {
      VariableDeclaration(:final initializer) => (initializer, null),
      FunctionDeclaration(:final functionExpression, :final isGetter)
          when isGetter =>
        (_bodyReturn(functionExpression.body), functionExpression.body),
      MethodDeclaration(:final body, :final isGetter) when isGetter => (
        _bodyReturn(body),
        body,
      ),
      _ => (null, null),
    };
    if (expr == null) return null;

    final locals = body == null ? const <String, Expression>{} : _locals(body);
    final expanding = {...s.expanding, key!};
    final result = value(
      expr,
      instance
          ? s.copyWith(
              locals: locals,
              params: const {},
              expanding: expanding,
              depth: s.depth + 1,
            )
          : _Scope.detached(
              locals: locals,
              expanding: expanding,
              depth: s.depth + 1,
            ),
    );
    if (!instance) _staticCache[key] = result;
    return result;
  }

  /// Inlines a call to a project function or method, binding arguments to
  /// its parameters, and returns what it returns.
  DartValue? _invoke(
    Element? element,
    List<DartValue> positional,
    Map<String, DartValue> named,
    _Scope s,
  ) {
    if (element is! ExecutableElement) return null;
    final key = _declKey(element);
    final decl = key == null ? null : declarations[key];
    if (decl == null || s.expanding.contains(key) || s.depth >= _maxDepth) {
      return null;
    }
    final FunctionBody body;
    switch (decl) {
      case FunctionDeclaration(:final functionExpression):
        body = functionExpression.body;
      case MethodDeclaration():
        body = decl.body;
      default:
        return null;
    }
    final expr = _bodyReturn(body);
    if (expr == null) return null;

    final params = <String, DartValue>{};
    final positionalParams = element.formalParameters
        .where((p) => p.isPositional)
        .toList();
    for (var i = 0; i < positional.length && i < positionalParams.length; i++) {
      params[positionalParams[i].name!] = positional[i];
    }
    params.addAll(named);

    final instance = _isInstanceMember(element);
    if (instance && !s.owners.contains(element.enclosingElement?.name)) {
      return null;
    }
    final expanding = {...s.expanding, key!};
    return value(
      expr,
      instance
          ? s.copyWith(
              locals: _locals(body),
              params: params,
              expanding: expanding,
              depth: s.depth + 1,
            )
          : _Scope.detached(
              locals: _locals(body),
              params: params,
              expanding: expanding,
              depth: s.depth + 1,
            ),
    );
  }

  /// Analyzes the initializer of a `const` declaration, following references
  /// into other libraries (including Flutter's own `Colors`, `Icons`, ...).
  DartValue? _constantOf(Element? element, int depth) {
    final variable = element is PropertyAccessorElement
        ? element.variable
        : element;
    if (variable is! VariableElement || !variable.isConst) return null;
    if (_constCache.containsKey(variable)) return _constCache[variable];
    if (depth > _maxConstDepth) return null;

    _constCache[variable] = null; // Cycle guard.
    final init = variable.constantInitializer;
    final result = init == null
        ? null
        : value(
            init,
            _Scope.detached(
              locals: const {},
              expanding: const {},
              depth: depth + 1,
            ),
          );
    return _constCache[variable] = result;
  }
}

class _LocalsCollector extends RecursiveAstVisitor<void> {
  final locals = <String, Expression>{};

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final init = node.initializer;
    if (init != null) locals.putIfAbsent(node.name.lexeme, () => init);
    super.visitVariableDeclaration(node);
  }
}
