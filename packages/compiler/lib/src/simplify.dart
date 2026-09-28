import 'package:flutter2figma_ir/flutter2figma_ir.dart';

/// Removes structural wrappers that Flutter needs but a designer doesn't:
///
/// * `Padding(child: Column(...))` → a Column frame with padding.
/// * `SizedBox(width: 100, child: Foo())` → Foo with a fixed width.
///
/// A wrapper is only folded into its child when the result renders
/// identically: same size on both axes and same child placement.
IrNode simplify(IrNode node) {
  if (node is! IrFrame) return node;
  node.children = [for (final c in node.children) simplify(c)];
  return _fold(node) ?? node;
}

/// Frames that only exist to space or size their child. Layout widgets
/// (Row, Column, Stack) and project widgets are authored structure and kept.
const _foldable = {'Padding', 'SizedBox', 'Container', 'Center', 'Align'};

IrNode? _fold(IrFrame wrapper) {
  if (!_foldable.contains(wrapper.name) ||
      wrapper.children.length != 1 ||
      wrapper.role != null ||
      !wrapper.isBare ||
      wrapper.direction == IrLayoutDirection.stack ||
      wrapper.minWidth != null ||
      wrapper.minHeight != null) {
    return null;
  }
  final child = wrapper.children.single;
  final padding = wrapper.padding;

  if (!padding.isZero) {
    // Padding moves inside the child, so the child must not paint (its fill
    // would spread under the padding) and must not already have padding.
    // Component occurrences must keep the component's own padding.
    if (child is! IrFrame ||
        child.instance != null ||
        !child.isBare ||
        !child.padding.isZero ||
        child.direction == IrLayoutDirection.stack) {
      return null;
    }
  }

  final width = _mergeAxis(
    wrapper.width,
    child.width,
    padding.horizontal,
    wrapperStart: _startAligned(wrapper, horizontalAxis: true),
    childStart: _startAligned(child, horizontalAxis: true),
  );
  final height = _mergeAxis(
    wrapper.height,
    child.height,
    padding.vertical,
    wrapperStart: _startAligned(wrapper, horizontalAxis: false),
    childStart: _startAligned(child, horizontalAxis: false),
  );
  if (width == null || height == null) return null;

  child
    ..width = width
    ..height = height
    ..origin = [...wrapper.origin, ...child.origin]
    ..position = wrapper.position ?? child.position
    ..source = child.source ?? wrapper.source;
  if (child is IrFrame) child.padding = child.padding + padding;
  return child;
}

/// Sizing of the merged node on one axis, or null if merging would change
/// the layout.
IrSizing? _mergeAxis(
  IrSizing outer,
  IrSizing inner,
  double padding, {
  required bool wrapperStart,
  required bool childStart,
}) {
  if (inner.isFill) return outer;
  if (outer.isHug) {
    return inner.isFixed ? IrSizing.fixed(inner.value! + padding) : inner;
  }
  if (outer.isFixed && inner.isFixed && inner.value! + padding == outer.value) {
    return outer;
  }
  // The outer box is bigger than the child. Growing the child to the outer
  // size only looks the same if both place content at the start.
  if (wrapperStart && childStart) return outer;
  return null;
}

bool _startAligned(IrNode node, {required bool horizontalAxis}) {
  if (node is IrText) {
    return horizontalAxis ? node.align == IrTextAlign.left : true;
  }
  final frame = node as IrFrame;
  if (frame.children.isEmpty) return true;
  final isMainAxis =
      (frame.direction == IrLayoutDirection.horizontal) == horizontalAxis;
  return isMainAxis
      ? frame.mainAlign == IrMainAlign.start
      : frame.crossAlign == IrCrossAlign.start;
}
