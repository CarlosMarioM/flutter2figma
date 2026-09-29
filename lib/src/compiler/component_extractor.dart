import 'dart:convert';

import 'package:flutter2figma/ir.dart';

/// Components the compiler marks on every occurrence (design-system
/// primitives), as opposed to project widgets, which must repeat.
const builtInComponents = {'Button'};

/// Turns the compiler's instance markers into components.
///
/// Occurrences of the same component whose subtrees differ only in text
/// share a variant; the text becomes instance overrides. Any other visual
/// difference (color, padding, structure) makes a separate variant, so an
/// instance always renders exactly like its occurrence.
class ComponentExtractor {
  ComponentExtractor({this.minUses = 2, this.sources = const {}});

  /// Project widgets used fewer times stay plain frames.
  final int minUses;

  /// Where project widgets are declared, by class name.
  final Map<String, String> sources;

  List<IrComponent> extract(List<IrScreen> screens) {
    final occurrences = <String, List<IrNode>>{};
    void visit(IrNode node) {
      final ref = node.instance;
      if (ref != null) (occurrences[ref.component] ??= []).add(node);
      if (node is IrFrame) node.children.forEach(visit);
    }

    for (final s in screens) {
      visit(s.root);
    }

    final components = <IrComponent>[];
    for (final MapEntry(key: name, value: nodes) in occurrences.entries) {
      if (!builtInComponents.contains(name) && nodes.length < minUses) {
        for (final n in nodes) {
          n.instance = null;
        }
        continue;
      }
      components.add(_component(name, nodes));
    }
    components.sort((a, b) => a.name.compareTo(b.name));
    return components;
  }

  IrComponent _component(String name, List<IrNode> nodes) {
    // Semantic props (e.g. Type/State) first, then visual signature.
    final groups = <String, Map<String, List<IrNode>>>{};
    for (final n in nodes) {
      final props = n.instance!.key;
      (groups[props] ??= {}).putIfAbsent(signature(n), () => []).add(n);
    }

    final variants = <IrComponentVariant>[];
    for (final bySignature in groups.values) {
      var index = 0;
      for (final members in bySignature.values) {
        index++;
        final props = {
          ...members.first.instance!.props,
          if (bySignature.length > 1) 'Variant': '$index',
        };
        for (final m in members) {
          m.instance = IrInstanceRef(name, props);
        }
        variants.add(IrComponentVariant(props, uses: members.length));
      }
    }
    return IrComponent(name: name, variants: variants, source: sources[name]);
  }
}

/// What must be identical for two occurrences to share a component variant:
/// everything except text content, provenance, and the root's own size and
/// placement (instances can be resized and positioned).
String signature(IrNode node) {
  final json = node.toJson()
    ..remove('width')
    ..remove('height')
    ..remove('position')
    ..remove('instance');
  return jsonEncode(_strip(json));
}

Object? _strip(Object? json) {
  if (json is List) return [for (final e in json) _strip(e)];
  if (json is! Map) return json;
  final isText = json['type'] == 'text';
  return {
    for (final MapEntry(:key, :value) in json.entries)
      if (key != 'source' &&
          key != 'origin' &&
          !(isText && (key == 'text' || key == 'name')))
        key: _strip(value),
  };
}
