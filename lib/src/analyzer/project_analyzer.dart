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
  ///
  /// A class that only wraps another screen class (e.g. `MenuScreen`
  /// providing blocs to `MenuPage`) is not listed separately.
  List<WidgetClass> get screens {
    final names = {
      for (final w in widgets)
        if (w.isScreen) w.name,
    };
    return [
      for (final w in widgets)
        if (w.isScreen && !w.scaffoldPath!.any(names.contains)) w,
    ];
  }
}

/// A `StatelessWidget` / `StatefulWidget` subclass declared in the project.
class WidgetClass {
  WidgetClass({required this.name, required this.source, required this.tree});

  final String name;
  final String source;

  /// What `build` returns, analyzed with no constructor arguments bound.
  final DartValue? tree;

  /// Whether `build` leads to a `Scaffold` through single-child wrappers
  /// (providers, builders, `PopScope`, project widgets, ...). Real apps
  /// rarely return the `Scaffold` directly.
  bool get isScreen => scaffoldPath != null;

  /// Project widget classes passed through on the way to the `Scaffold`;
  /// empty when this class builds it itself. Null when there is none.
  late final List<String>? scaffoldPath = _findScaffold(tree, const [], 0);
}

/// App-level roots are not screens even though they lead to one.
const _appWidgets = {'MaterialApp', 'CupertinoApp', 'WidgetsApp'};

List<String>? _findScaffold(DartValue? v, List<String> via, int depth) {
  if (v == null || depth > 16) return null;
  switch (v) {
    case ObjectValue(isWidget: true):
      if (v.isFlutter && v.type == 'Scaffold') return via;
      if (v.isFlutter && _appWidgets.contains(v.type)) return null;
      if (v.build != null) {
        return _findScaffold(v.build, [...via, v.type], depth + 1);
      }
      final builder = v.named['builder'];
      return _findScaffold(v.named['child'], via, depth + 1) ??
          (builder is FunctionValue
              ? _findScaffold(builder.returns, via, depth + 1)
              : null);
    case ConditionalValue(:final then, :final otherwise):
      // Prefer the branch that builds the Scaffold most directly:
      // `if (done) return OtherScreen(); return Scaffold(...)` is a screen
      // of its own, not a wrapper of OtherScreen.
      final a = _findScaffold(then, via, depth + 1);
      final b = _findScaffold(otherwise, via, depth + 1);
      if (a == null || b == null) return a ?? b;
      return b.length < a.length ? b : a;
    case CallValue(:final result):
      return _findScaffold(result, via, depth + 1);
    case RefValue(:final resolved):
      return _findScaffold(resolved, via, depth + 1);
    default:
      return null;
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
    final constructors = <String, ConstructorDeclaration>{};
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
                case ConstructorDeclaration():
                  final ctor = member.declaredFragment?.element;
                  if (ctor != null) constructors[_ctorKey(ctor)] = member;
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

    final expander = _Expander(root, index, declarations, constructors);
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

/// `Foo()` and `Foo.named()` constructors of a class, by class and name.
String _ctorKey(ConstructorElement c) {
  final name = c.name;
  return '${_key(c.enclosingElement)}:${name == null || name == 'new' ? '' : name}';
}

/// Widgets whose `builder: (context, state)` receives the bloc's state.
const _blocBuilders = {'BlocBuilder', 'BlocConsumer'};

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
  _Expander(this.root, this.index, this.declarations, this.constructors);

  static const _maxDepth = 16;
  static const _maxConstDepth = 8;

  final String root;
  final Map<String, ClassDeclaration> index;

  /// Project variables, getters, functions and methods by [_declKey].
  final Map<String, AstNode> declarations;

  /// Project constructors by [_ctorKey], for parameter defaults and blocs'
  /// initial states.
  final Map<String, ConstructorDeclaration> constructors;
  final _initialStates = <String, DartValue?>{};
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
    if (build == null) return null;
    return _returns(
      build.body,
      _Scope(
        bindings: bindings,
        locals: _locals(build),
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

  /// What a function body returns. Early returns become a conditional
  /// chain, so every branch is kept:
  ///
  ///     if (state is Loaded) { return Content(); }   →   state is Loaded
  ///     return Spinner();                                 ? Content() : Spinner()
  DartValue? _returns(FunctionBody? body, _Scope s) => switch (body) {
    ExpressionFunctionBody(:final expression) => value(expression, s),
    BlockFunctionBody(:final block) => _statements(block.statements, s),
    _ => null,
  };

  DartValue? _statements(List<Statement> statements, _Scope s) {
    for (var i = 0; i < statements.length; i++) {
      final st = statements[i];
      if (st is ReturnStatement) {
        final e = st.expression;
        return e == null ? null : value(e, s);
      }
      if (st is IfStatement) {
        final known = _condition(st.expression, s);
        if (known != null) {
          final taken = known ? st.thenStatement : st.elseStatement;
          final result = taken == null ? null : _branch(taken, s);
          if (result != null) return result;
          continue;
        }
        final then = _branch(st.thenStatement, s);
        final otherwise = st.elseStatement == null
            ? null
            : _branch(st.elseStatement!, s);
        if (then == null && otherwise == null) continue;
        DartValue? rest() => _statements(statements.sublist(i + 1), s);
        final condition = st.expression.toSource();
        if (then != null) {
          final alternative = otherwise ?? rest();
          return alternative == null
              ? then
              : ConditionalValue(
                  condition,
                  then,
                  alternative,
                  source: location(st),
                );
        }
        final alternative = rest();
        return alternative == null
            ? otherwise
            : ConditionalValue(
                '!($condition)',
                otherwise!,
                alternative,
                source: location(st),
              );
      }
    }
    return null;
  }

  /// Evaluates a condition when its values are statically known (literals,
  /// constants, a bloc's initial state), else null.
  bool? _condition(Expression e, _Scope s) {
    switch (e) {
      case BooleanLiteral(:final value):
        return value;
      case ParenthesizedExpression(:final expression):
        return _condition(expression, s);
      case PrefixExpression(operator: Token(lexeme: '!'), :final operand):
        final inner = _condition(operand, s);
        return inner == null ? null : !inner;
      case BinaryExpression(operator: Token(lexeme: '&&')):
        final a = _condition(e.leftOperand, s);
        final b = _condition(e.rightOperand, s);
        if (a == false || b == false) return false;
        return a == true && b == true ? true : null;
      case BinaryExpression(operator: Token(lexeme: '||')):
        final a = _condition(e.leftOperand, s);
        final b = _condition(e.rightOperand, s);
        if (a == true || b == true) return true;
        return a == false && b == false ? false : null;
      case BinaryExpression(operator: Token(lexeme: '==' || '!=')):
        final equal = _equal(
          _known(value(e.leftOperand, s)),
          _known(value(e.rightOperand, s)),
        );
        if (equal == null) return null;
        return e.operator.lexeme == '==' ? equal : !equal;
      default:
        final known = _known(value(e, s));
        return known is LiteralValue && known.value is bool
            ? known.value as bool
            : null;
    }
  }

  /// A value with references, project calls and field reads of known
  /// objects followed, or null when it depends on runtime state.
  DartValue? _known(DartValue v, [int depth = 0]) {
    if (depth > 16) return null;
    return switch (v) {
      LiteralValue() || ObjectValue() || ListValue() || MapValue() => v,
      RefValue(:final resolved?) => _known(resolved, depth + 1),
      // Enum values and other constants without a known initializer.
      RefValue() => v,
      CallValue(:final result?) => _known(result, depth + 1),
      BinaryValue(:final operator, :final left, :final right) => switch ((
        _known(left, depth + 1),
        _known(right, depth + 1),
      )) {
        (LiteralValue(value: final a), LiteralValue(value: final b)) =>
          switch (applyArithmetic(operator, a, b)) {
            final Object v => LiteralValue(v),
            null => null,
          },
        _ => null,
      },
      AccessValue(:final target, :final name) => switch (_known(
        target,
        depth + 1,
      )) {
        ObjectValue(:final named) when named.containsKey(name) => _known(
          named[name]!,
          depth + 1,
        ),
        ListValue(:final items) when name == 'length' => LiteralValue(
          items.length,
        ),
        MapValue(:final entries) when name == 'length' => LiteralValue(
          entries.length,
        ),
        ListValue(:final items) when name == 'isEmpty' => LiteralValue(
          items.isEmpty,
        ),
        ListValue(:final items) when name == 'isNotEmpty' => LiteralValue(
          items.isNotEmpty,
        ),
        _ => null,
      },
      _ => null,
    };
  }

  /// Whether two known values are equal, or null if that can't be decided.
  bool? _equal(DartValue? a, DartValue? b) {
    if (a == null || b == null) return null;
    if (a is LiteralValue && b is LiteralValue) return a.value == b.value;
    // A known object is never `null`.
    final aNull = a is LiteralValue && a.value == null;
    final bNull = b is LiteralValue && b.value == null;
    if (aNull && b is! LiteralValue) return false;
    if (bNull && a is! LiteralValue) return false;
    // Enum-like constants: same reference, same value.
    if (a is RefValue && b is RefValue) {
      return a.dotted == b.dotted ? true : null;
    }
    return null;
  }

  DartValue? _branch(Statement st, _Scope s) => switch (st) {
    Block(:final statements) => _statements(statements, s),
    _ => _statements([st], s),
  };

  /// The expression a function body returns: its `=>` expression, or the
  /// last top-level `return`. Used where an expression, not a value, is
  /// needed (e.g. `createState`).
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
              final part = value(element.expression, s);
              // `'${state.crossWins}'` with a known state reads `0`.
              buffer.write(_stringOf(_known(part) ?? part));
          }
        }
        return LiteralValue(buffer.toString(), source: loc);
      case PrefixExpression(operator: Token(lexeme: '-')):
        final inner = value(e.operand, s);
        final known = _known(inner);
        if (known is LiteralValue && known.value is num) {
          return LiteralValue(-(known.value as num), source: loc);
        }
        return BinaryValue('-', const LiteralValue(0), inner, source: loc);
      case ParenthesizedExpression():
        return value(e.expression, s);
      case BinaryExpression(
        operator: Token(lexeme: '+' || '-' || '*' || '/' || '~/'),
      ):
        // `size / 2 - 1`: folded when both sides are known.
        final left = value(e.leftOperand, s);
        final right = value(e.rightOperand, s);
        final l = _known(left), r = _known(right);
        final folded = l is LiteralValue && r is LiteralValue
            ? applyArithmetic(e.operator.lexeme, l.value, r.value)
            : null;
        return folded != null
            ? LiteralValue(folded, source: loc)
            : BinaryValue(e.operator.lexeme, left, right, source: loc);
      case BinaryExpression(operator: Token(lexeme: '??')):
        // `a ?? b`: a known `a` decides. An unknown one is assumed null, as
        // it usually is on the first frame (`Text(icon ?? '')` on an empty
        // board): the fallback is shown.
        final left = value(e.leftOperand, s);
        final right = value(e.rightOperand, s);
        final known = _known(left);
        if (known is LiteralValue) return known.value == null ? right : left;
        if (known is ObjectValue || known is ListValue || known is MapValue) {
          return left;
        }
        return ConditionalValue(
          '${e.leftOperand.toSource()} == null',
          right,
          left,
          source: loc,
        );
      case AsExpression():
        return value(e.expression, s);
      case PostfixExpression(operator: Token(lexeme: '!')):
        return value(e.operand, s);
      case InstanceCreationExpression():
        return _object(e, s, loc);
      case MethodInvocation(
            methodName: SimpleIdentifier(name: 'map'),
            target: final target?,
          )
          when e.argumentList.arguments.length == 1 &&
              e.argumentList.arguments.single.argumentExpression
                  is FunctionExpression:
        // `<literal list>.map((x) => ...)`: one result per known item.
        final fn =
            e.argumentList.arguments.single.argumentExpression
                as FunctionExpression;
        final items = _literalItems(target, s);
        final param = fn.parameters?.parameters.singleOrNull?.name?.lexeme;
        return CallValue(
          value(target, s),
          'map',
          positional: [value(fn, s)],
          result: items == null || param == null
              ? null
              : ListValue([
                  for (final item in items)
                    ?_returns(
                      fn.body,
                      s.copyWith(params: {...s.params, param: item}),
                    ),
                ], source: loc),
          source: loc,
        );
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
        // context.read<MyBloc>().state, context.watch<...>(),
        // BlocProvider.of<...>(context): the bloc's initial state.
        if (name == 'state' &&
            target is MethodInvocation &&
            const {'read', 'watch', 'of'}.contains(target.methodName.name)) {
          final bloc = target.typeArguments?.arguments.firstOrNull;
          final state = bloc is NamedType ? _initialState(bloc.element) : null;
          if (state != null) return state;
        }
        return AccessValue(value(target, s), name, source: loc);
      case SimpleIdentifier():
        return _identifier(e, s, loc);
      case SwitchExpression():
        // Chain the cases like `?:`: the first case is the `then` branch.
        DartValue? chain;
        for (final c in e.cases.reversed) {
          final result = value(c.expression, s);
          chain = chain == null
              ? result
              : ConditionalValue(
                  '${e.expression.toSource()} is ${c.guardedPattern.toSource()}',
                  result,
                  chain,
                  source: location(c),
                );
        }
        return chain ?? UnknownValue(e.toSource(), source: loc);
      case ConditionalExpression():
        switch (_condition(e.condition, s)) {
          case true:
            return value(e.thenExpression, s);
          case false:
            return value(e.elseExpression, s);
          case null:
            break;
        }
        return ConditionalValue(
          e.condition.toSource(),
          value(e.thenExpression, s),
          value(e.elseExpression, s),
          source: loc,
        );
      case FunctionExpression():
        return FunctionValue(returns: _returns(e.body, s), source: loc);
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
    LiteralValue(value: null) => 'null',
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
        case IfElement() when _condition(element.expression, s) != null:
          final taken = _condition(element.expression, s)!
              ? element.thenElement
              : element.elseElement;
          if (taken != null) out.addAll(_collection([taken], s));
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
        case ForElement():
          // `for (final x in <literal list>)`: one body per known item.
          final parts = element.forLoopParts;
          if (parts is ForEachPartsWithDeclaration) {
            final items = _literalItems(parts.iterable, s);
            if (items != null) {
              final name = parts.loopVariable.name.lexeme;
              for (final item in items) {
                out.addAll(
                  _collection([
                    element.body,
                  ], s.copyWith(params: {...s.params, name: item})),
                );
              }
              continue;
            }
          }
          final body = _collection([element.body], s);
          if (body.length == 1) {
            out.add(
              LoopValue(
                element.forLoopParts.toSource(),
                body.single,
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

  /// Default values of the named parameters a project constructor call
  /// leaves out: `{this.color = Colors.blue}` and freezed's
  /// `@Default(Colors.blue) Color color`.
  Map<String, DartValue> _defaults(InstanceCreationExpression e, _Scope s) {
    final ctor = e.constructorName.element;
    final decl = ctor == null ? null : constructors[_ctorKey(ctor.baseElement)];
    if (decl == null) return const {};
    final passed = {
      for (final a in e.argumentList.arguments.whereType<NamedArgument>())
        a.name.lexeme,
    };
    final defaults = <String, DartValue>{};
    for (final param in decl.parameters.parameters) {
      final name = param.name?.lexeme;
      if (name == null || !param.isNamed || passed.contains(name)) continue;
      Expression? value = param.defaultClause?.value;
      if (value == null) {
        for (final annotation in param.metadata) {
          if (annotation.name.name == 'Default') {
            value =
                annotation.arguments?.arguments.firstOrNull?.argumentExpression;
          }
        }
      }
      if (value == null && param.isOptionalNamed) {
        defaults[name] = const LiteralValue(null); // Nullable, not passed.
      } else if (value != null) {
        defaults[name] = this.value(
          value,
          _Scope.detached(
            locals: const {},
            expanding: s.expanding,
            depth: s.depth + 1,
          ),
        );
      }
    }
    return defaults;
  }

  /// The state a bloc or cubit starts with: the argument of `super(...)` in
  /// its constructor, e.g. `ThemeCubit() : super(ThemeState.amber())`.
  DartValue? _initialState(Element? bloc) {
    if (bloc is! InterfaceElement) return null;
    final key = _key(bloc);
    if (_initialStates.containsKey(key)) return _initialStates[key];
    _initialStates[key] = null; // Cycle guard.
    final ctor = constructors['$key:'];
    final superCall = ctor?.initializers
        .whereType<SuperConstructorInvocation>()
        .firstOrNull;
    final arg = superCall?.argumentList.arguments.firstOrNull;
    final state = arg == null
        ? null
        : value(
            arg.argumentExpression,
            _Scope.detached(locals: const {}, expanding: const {}, depth: 1),
          );
    return _initialStates[key] = state;
  }

  DartValue _object(InstanceCreationExpression e, _Scope s, String? loc) {
    final classElement = e.constructorName.type.element;
    final positional = _positional(e.argumentList, s);
    final named = {
      ..._named(e.argumentList, s),
      // Arguments not passed take the constructor's defaults.
      ..._defaults(e, s),
    };
    final isWidget = _isWidgetType(e.staticType);
    // Project values (states, enum constants such as `cross('Cross', '❌')`)
    // also expose positional arguments by parameter name, so a later
    // `DrawnElement.cross.icon` can read them.
    if (!isWidget && _inProject(classElement)) {
      final formals = e.constructorName.element?.formalParameters ?? const [];
      final positionalFormals = formals.where((p) => p.isPositional).toList();
      for (
        var i = 0;
        i < positional.length && i < positionalFormals.length;
        i++
      ) {
        final name = positionalFormals[i].name;
        if (name != null) named.putIfAbsent(name, () => positional[i]);
      }
    }

    // BlocBuilder<MyBloc, MyState>(builder: (context, state) => ...): the
    // builder sees the bloc's initial state.
    final typeName = e.constructorName.type.name.lexeme;
    final libraryUri = classElement?.library?.uri.toString() ?? '';
    if (_blocBuilders.contains(typeName) && libraryUri.contains('bloc')) {
      final bloc = e.constructorName.type.typeArguments?.arguments.firstOrNull;
      final state = bloc is NamedType ? _initialState(bloc.element) : null;
      final builderArg = e.argumentList.arguments
          .whereType<NamedArgument>()
          .where((a) => a.name.lexeme == 'builder')
          .firstOrNull
          ?.argumentExpression;
      final params = builderArg is FunctionExpression
          ? builderArg.parameters?.parameters
          : null;
      final stateParam = params != null && params.length >= 2
          ? params[1].name?.lexeme
          : null;
      if (state != null && stateParam != null) {
        named['builder'] = FunctionValue(
          returns: _returns(
            (builderArg as FunctionExpression).body,
            s.copyWith(params: {...s.params, stateParam: state}),
          ),
          source: location(builderArg),
        );
      }
    }

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
      inProject: _inProject(classElement),
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

    if (element is LocalVariableElement && s.params.containsKey(name)) {
      return s.params[name]!; // A loop variable bound to a known item.
    }
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

  /// Items of an iterable whose elements are statically known (a list
  /// literal, possibly behind a field, getter or const), else null.
  List<DartValue>? _literalItems(Expression iterable, _Scope s) {
    var v = value(iterable, s);
    for (var i = 0; i < 8; i++) {
      v = switch (v) {
        RefValue(:final resolved?) => resolved,
        CallValue(:final result?) => result,
        _ => v,
      };
    }
    if (v is! ListValue) return null;
    final items = v.items;
    // Loops over unknown or nested-loop contents stay symbolic.
    if (items.any((i) => i is LoopValue || i is UnknownValue)) return null;
    return items.length <= 50 ? items : null;
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

    final (Expression? init, FunctionBody? body) = switch (decl) {
      VariableDeclaration(:final initializer) => (initializer, null),
      FunctionDeclaration(:final functionExpression, :final isGetter)
          when isGetter =>
        (null, functionExpression.body),
      MethodDeclaration(:final body, :final isGetter) when isGetter => (
        null,
        body,
      ),
      _ => (null, null),
    };
    if (init == null && body == null) return null;

    final locals = body == null ? const <String, Expression>{} : _locals(body);
    final expanding = {...s.expanding, key!};
    final scope = instance
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
          );
    final result = init != null ? value(init, scope) : _returns(body, scope);
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
    return _returns(
      body,
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
