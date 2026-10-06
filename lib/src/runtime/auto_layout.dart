import 'dart:math';

import 'package:flutter2figma/ir.dart';

/// A node's box, relative to its parent: (left, top, width, height).
typedef Box = (double, double, double, double);

/// Turns absolutely positioned runtime frames into Figma auto layout where
/// that reproduces Flutter's positions exactly.
///
/// For each frame (children first), children that sit in one row or column
/// become an auto-layout flow:
///
/// - padding is the space before the first and after the last child, and
///   the gap the smallest space between children; larger spaces become
///   spacer frames (Flutter's `SizedBox` spacers, mirrored);
/// - the cross axis alignment (start, center, end) is the one most children
///   follow; children spanning the whole cross axis fill it, and children
///   that follow no alignment stay absolutely positioned inside the flow;
/// - `Expanded`/`Flexible` children ([flexFactor]) fill the main axis, and
///   frames hug their content where that gives the same size.
///
/// Each converted frame is checked by recomputing every child's position
/// as Figma will lay it out; a frame that would move anything by more than
/// half a pixel stays absolute.
class AutoLayout {
  AutoLayout({
    required this.boxes,
    required this.flexDirection,
    required this.flexFactor,
  });

  /// Every node's box as captured.
  final Expando<Box> boxes;

  /// The direction of a frame that was a Flutter Row/Column.
  final Expando<IrLayoutDirection> flexDirection;

  /// `flex` of children of a Row/Column (Expanded, Flexible).
  final Expando<int> flexFactor;

  static const _eps = 0.5;

  /// The largest margin read as padding rather than centering.
  static const _pagePadding = 24.0;

  /// Converts [frame]'s subtree; the frame itself keeps its own sizing.
  void apply(IrFrame frame) {
    for (final c in frame.children) {
      if (c is IrFrame) apply(c);
    }
    if (frame.direction != IrLayoutDirection.stack) return;
    // Turned children only exist in absolute layout.
    if (frame.children.any((c) => c.rotation != 0)) return;
    if (_adopt(frame)) {
      // Backgrounds took in their content: lay those out too.
      for (final c in frame.children) {
        if (c is IrFrame && c.direction == IrLayoutDirection.stack) apply(c);
      }
    }
    if (frame.role == 'icon' || frame.children.isEmpty) return;
    final size = boxes[frame];
    if (size == null) return;
    final (_, _, width, height) = size;
    if (frame.children.any((c) => boxes[c] == null || c.position == null)) {
      return;
    }

    _Plan? best;
    final hint = flexDirection[frame];
    for (final direction in [
      ?hint,
      IrLayoutDirection.vertical,
      IrLayoutDirection.horizontal,
    ]) {
      final plan = _plan(frame, direction, width, height);
      if (plan == null) continue;
      if (best == null || plan.absolute.length < best.absolute.length) {
        best = plan;
      }
      if (best.absolute.isEmpty) break;
    }
    // Mostly overlapping children (a background with content on top) are a
    // stack, not a flow.
    if (best == null || best.flow.length <= best.absolute.length) return;
    _commit(frame, best, width, height);
  }

  /// Siblings painted on top of a frame and inside it become its children,
  /// as a decoration wraps its child in Flutter (a text field's background
  /// and its hint, a card and its content). Returns whether any moved.
  bool _adopt(IrFrame frame) {
    var moved = false;
    for (var i = 0; i < frame.children.length; i++) {
      final host = frame.children[i];
      // Pixels (images, a painter's shadows) hold nothing.
      if (host is! IrFrame ||
          host.role == 'icon' ||
          host.role == 'image' ||
          host.direction != IrLayoutDirection.stack ||
          boxes[host] == null) {
        continue;
      }
      final (hx, hy, hw, hh) = boxes[host]!;
      final guests = [
        for (final c in frame.children.skip(i + 1))
          if (boxes[c] case (final x, final y, final w, final h)
              when x >= hx - _eps &&
                  y >= hy - _eps &&
                  x + w <= hx + hw + _eps &&
                  y + h <= hy + hh + _eps &&
                  (w < hw - _eps || h < hh - _eps))
            c,
      ];
      if (guests.isEmpty) continue;
      for (final g in guests) {
        final (x, y, w, h) = boxes[g]!;
        frame.children.remove(g);
        g.position = IrPosition(left: _r(x - hx), top: _r(y - hy));
        boxes[g] = (x - hx, y - hy, w, h);
        host.children.add(g);
      }
      moved = true;
    }
    return moved;
  }

  /// How [frame]'s children would flow in [direction], or null when they
  /// overlap along it.
  _Plan? _plan(
    IrFrame frame,
    IrLayoutDirection direction,
    double width,
    double height,
  ) {
    final vertical = direction == IrLayoutDirection.vertical;
    final mainSize = vertical ? height : width;
    final crossSize = vertical ? width : height;
    double start(IrNode n) => vertical ? boxes[n]!.$2 : boxes[n]!.$1;
    double length(IrNode n) => vertical ? boxes[n]!.$4 : boxes[n]!.$3;
    double crossStart(IrNode n) => vertical ? boxes[n]!.$1 : boxes[n]!.$2;
    double crossLength(IrNode n) => vertical ? boxes[n]!.$3 : boxes[n]!.$4;

    // Cross axis: the alignment most children follow.
    final kids = frame.children.toList();
    final alignments = {
      IrCrossAlign.start: [
        for (final c in kids)
          if (crossStart(c) >= -_eps) c,
      ],
      IrCrossAlign.center: [
        for (final c in kids)
          if (((crossStart(c) + crossLength(c) / 2) - crossSize / 2).abs() <
              _eps)
            c,
      ],
      IrCrossAlign.end: [
        for (final c in kids)
          if (crossStart(c) + crossLength(c) <= crossSize + _eps) c,
      ],
    };
    // Start alignment needs every child at the same offset; end alignment
    // the same distance from the end.
    List<IrNode> sameOffset(List<IrNode> list, double Function(IrNode) key) {
      if (list.isEmpty) return list;
      final counts = <double, List<IrNode>>{};
      for (final c in list) {
        final k = (key(c) * 2).roundToDouble() / 2;
        counts.putIfAbsent(k, () => []).add(c);
      }
      return counts.values.reduce((a, b) => a.length >= b.length ? a : b);
    }

    alignments[IrCrossAlign.start] = sameOffset(
      alignments[IrCrossAlign.start]!,
      crossStart,
    );
    alignments[IrCrossAlign.end] = sameOffset(
      alignments[IrCrossAlign.end]!,
      (c) => crossSize - crossStart(c) - crossLength(c),
    );
    // The alignment most children follow; on a tie (a single child), the
    // one needing the least padding: an end-aligned child is "end", not
    // "start" after a large padding.
    double padding(IrCrossAlign a) {
      final list = alignments[a]!;
      if (list.isEmpty) return double.infinity;
      return switch (a) {
        IrCrossAlign.start => list.map(crossStart).reduce(min),
        IrCrossAlign.end =>
          list
              .map((c) => crossSize - crossStart(c) - crossLength(c))
              .reduce(min),
        // Centered with a small margin is page padding around stretched
        // content (start + fill); a wide margin is real centering.
        _ =>
          list.map(crossStart).reduce(min) <= _pagePadding
              ? double.infinity
              : 0,
      };
    }

    final align = [IrCrossAlign.start, IrCrossAlign.center, IrCrossAlign.end]
        .reduce((a, b) {
          final ca = alignments[a]!.length, cb = alignments[b]!.length;
          if (cb != ca) return cb > ca ? b : a;
          return padding(b) < padding(a) ? b : a;
        });
    final inFlow = alignments[align]!.toSet();
    // A child that contains another one is a background behind it (a
    // selection indicator, a highlight): absolute, so the rest can flow.
    bool contains(IrNode a, IrNode b) {
      final (ax, ay, aw, ah) = boxes[a]!;
      final (bx, by, bw, bh) = boxes[b]!;
      return a != b &&
          ax <= bx + _eps &&
          ay <= by + _eps &&
          ax + aw >= bx + bw - _eps &&
          ay + ah >= by + bh - _eps &&
          (aw > bw + _eps || ah > bh + _eps);
    }

    inFlow.removeWhere((a) => kids.any((b) => contains(a, b)));

    // Main axis: the flow children must not overlap along it.
    final flow = [
      for (final c in kids)
        if (inFlow.contains(c)) c,
    ]..sort((a, b) => start(a).compareTo(start(b)));
    for (var i = 1; i < flow.length; i++) {
      if (start(flow[i]) < start(flow[i - 1]) + length(flow[i - 1]) - _eps) {
        return null;
      }
    }
    if (flow.isEmpty) return null;
    final leading = start(flow.first);
    final trailing = mainSize - start(flow.last) - length(flow.last);
    if (leading < -_eps || trailing < -_eps) return null;
    final gaps = [
      for (var i = 1; i < flow.length; i++)
        start(flow[i]) - start(flow[i - 1]) - length(flow[i - 1]),
    ];
    // The smallest space is the gap; a larger one gets a spacer, which
    // itself sits between two gaps (space = gap + spacer + gap). When a
    // space is too small for that, use spacers only (gap 0).
    var gap = gaps.isEmpty ? 0.0 : max(0.0, gaps.reduce(min));
    if (gaps.any((g) => g - gap > _eps && g < 2 * gap - _eps)) gap = 0;

    // Cross padding: the offset shared by the flow (start/end), or the
    // margin of the widest child (center).
    // Padding is usually symmetric (Padding, EdgeInsets.symmetric): the
    // far side mirrors the near one when every child fits inside it, so
    // only children spanning that inner area stretch.
    double crossLead, crossTrail;
    final endSpace = flow
        .map((c) => crossSize - crossStart(c) - crossLength(c))
        .reduce(min);
    final startSpace = flow.map(crossStart).reduce(min);
    switch (align) {
      case IrCrossAlign.start:
        crossLead = crossStart(flow.first);
        crossTrail = endSpace >= crossLead - _eps ? crossLead : endSpace;
      case IrCrossAlign.end:
        crossTrail =
            crossSize - crossStart(flow.first) - crossLength(flow.first);
        crossLead = startSpace >= crossTrail - _eps ? crossTrail : startSpace;
      default:
        // Centered children need no cross padding: the frame's size
        // centers them, and they keep their own width.
        crossLead = crossTrail = 0;
    }
    if (crossLead < -_eps || crossTrail < -_eps) return null;

    return _Plan(
      direction: direction,
      align: align,
      flow: flow,
      absolute: [
        for (final c in kids)
          if (!inFlow.contains(c)) c,
      ],
      leading: max(0, leading),
      trailing: max(0, trailing),
      gap: gap,
      gaps: gaps,
      crossLead: max(0, crossLead),
      crossTrail: max(0, crossTrail),
    );
  }

  void _commit(IrFrame frame, _Plan plan, double width, double height) {
    final vertical = plan.direction == IrLayoutDirection.vertical;
    final crossSize = vertical ? width : height;
    double crossLength(IrNode n) => vertical ? boxes[n]!.$3 : boxes[n]!.$4;
    final innerCross = crossSize - plan.crossLead - plan.crossTrail;

    // Children in flow order, with spacers where the space is larger than
    // the gap. Absolute children keep their place in paint order: before
    // the flow if they were painted before it (backgrounds), else after.
    final firstFlowIndex = frame.children.indexOf(
      frame.children.firstWhere(plan.flow.contains),
    );
    final before = <IrNode>[], after = <IrNode>[];
    for (final c in plan.absolute) {
      (frame.children.indexOf(c) < firstFlowIndex ? before : after).add(c);
    }
    final flowWithSpacers = <IrNode>[];
    for (var i = 0; i < plan.flow.length; i++) {
      if (i > 0) {
        final space = plan.gaps[i - 1];
        final extra = space - plan.gap > _eps ? space - 2 * plan.gap : 0.0;
        if (extra > _eps) {
          final spacer = IrFrame(
            name: 'Spacer',
            origin: const ['SizedBox'],
            width: IrSizing.fixed(vertical ? 1 : _r(extra)),
            height: IrSizing.fixed(vertical ? _r(extra) : 1),
          );
          boxes[spacer] = (0, 0, vertical ? 1 : extra, vertical ? extra : 1);
          flowWithSpacers.add(spacer);
        }
      }
      flowWithSpacers.add(plan.flow[i]);
    }

    // Remember the stack layout, to undo it if the check fails.
    final saved = (
      frame.children.toList(),
      {for (final c in frame.children) c: (c.position, c.width, c.height)},
    );

    frame
      ..direction = plan.direction
      ..gap = _r(plan.gap)
      ..mainAlign = IrMainAlign.start
      ..crossAlign = plan.align
      ..padding = vertical
          ? IrInsets(
              top: _r(plan.leading),
              bottom: _r(plan.trailing),
              left: _r(plan.crossLead),
              right: _r(plan.crossTrail),
            )
          : IrInsets(
              left: _r(plan.leading),
              right: _r(plan.trailing),
              top: _r(plan.crossLead),
              bottom: _r(plan.crossTrail),
            )
      ..children.replaceRange(0, frame.children.length, [
        ...before,
        ...flowWithSpacers,
        ...after,
      ]);
    // Expanded/Flexible fill the main axis when Figma's equal share of the
    // free space is their size (equal flex factors); full-width children
    // stretch.
    double mainLength(IrNode n) => vertical ? boxes[n]!.$4 : boxes[n]!.$3;
    final flexing = [
      for (final c in flowWithSpacers)
        if ((flexFactor[c] ?? 0) > 0) c,
    ];
    final fillMain =
        flexing.isNotEmpty &&
        flexing.every(
          (c) => (mainLength(c) - mainLength(flexing.first)).abs() < _eps,
        );
    for (final c in flowWithSpacers) {
      c.position = null;
      if (fillMain && flexing.contains(c)) {
        if (vertical) {
          c.height = const IrSizing.fill();
        } else {
          c.width = const IrSizing.fill();
        }
      }
      // A vector is as big as its outline: stretching would distort it.
      if (c is! IrVector &&
          c.name != 'Spacer' &&
          (crossLength(c) - innerCross).abs() < _eps) {
        if (vertical) {
          c.width = const IrSizing.fill();
        } else {
          c.height = const IrSizing.fill();
        }
      }
    }

    if (!_matches(frame, plan, saved.$2, width, height)) {
      frame
        ..direction = IrLayoutDirection.stack
        ..gap = 0
        ..padding = IrInsets.zero
        ..mainAlign = IrMainAlign.start
        ..crossAlign = IrCrossAlign.start
        ..children.replaceRange(0, frame.children.length, saved.$1);
      for (final MapEntry(key: c, value: (position, w, h))
          in saved.$2.entries) {
        c
          ..position = position
          ..width = w
          ..height = h;
      }
    }
  }

  /// Lays the flow out as Figma will and compares with Flutter's boxes.
  bool _matches(
    IrFrame frame,
    _Plan plan,
    Map<IrNode, (IrPosition?, IrSizing, IrSizing)> original,
    double width,
    double height,
  ) {
    final vertical = plan.direction == IrLayoutDirection.vertical;
    final mainSize = vertical ? height : width;
    final crossSize = vertical ? width : height;
    final pad = frame.padding;
    final mainLead = vertical ? pad.top : pad.left;
    final mainTrail = vertical ? pad.bottom : pad.right;
    final crossLead = vertical ? pad.left : pad.top;
    final crossTrail = vertical ? pad.right : pad.bottom;
    final flow = [
      for (final c in frame.children)
        if (c.position == null) c,
    ];
    double mainOf(IrNode c) => vertical ? boxes[c]!.$4 : boxes[c]!.$3;
    double crossOf(IrNode c) => vertical ? boxes[c]!.$3 : boxes[c]!.$4;
    bool fillsMain(IrNode c) =>
        (vertical ? c.height : c.width).mode == SizingMode.fill;

    // Fill children share what fixed children and gaps leave.
    final fixed = flow
        .where((c) => !fillsMain(c))
        .fold(0.0, (sum, c) => sum + mainOf(c));
    final fills = flow.where(fillsMain).toList();
    final free =
        mainSize - mainLead - mainTrail - fixed - frame.gap * (flow.length - 1);
    if (fills.isNotEmpty) {
      final share = free / fills.length;
      if (fills.any((c) => (mainOf(c) - share).abs() > _eps)) return false;
    } else if (free.abs() > _eps) {
      return false;
    }

    var cursor = mainLead;
    for (final c in flow) {
      final (x, y, _, _) = boxes[c]!;
      final mainPos = vertical ? y : x;
      final crossPos = vertical ? x : y;
      if (c.name != 'Spacer' && (mainPos - cursor).abs() > _eps) return false;
      final inner = crossSize - crossLead - crossTrail;
      final expected = switch (frame.crossAlign) {
        IrCrossAlign.center => crossLead + (inner - crossOf(c)) / 2,
        IrCrossAlign.end => crossSize - crossTrail - crossOf(c),
        _ => crossLead,
      };
      if (c.name != 'Spacer' && (crossPos - expected).abs() > _eps) {
        return false;
      }
      cursor += mainOf(c) + frame.gap;
    }
    return true;
  }

  static double _r(double v) => (v * 100).roundToDouble() / 100;
}

class _Plan {
  _Plan({
    required this.direction,
    required this.align,
    required this.flow,
    required this.absolute,
    required this.leading,
    required this.trailing,
    required this.gap,
    required this.gaps,
    required this.crossLead,
    required this.crossTrail,
  });

  final IrLayoutDirection direction;
  final IrCrossAlign align;
  final List<IrNode> flow;
  final List<IrNode> absolute;
  final double leading, trailing, gap, crossLead, crossTrail;
  final List<double> gaps;
}
