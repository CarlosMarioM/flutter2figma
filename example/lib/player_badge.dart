import 'package:flutter/material.dart';

/// Enum constants with fields, read through the constant.
enum Player {
  cross('Cross', '❌'),
  circle('Circle', '⭕️');

  const Player(this.label, this.symbol);
  final String label, symbol;
}

/// `??` with a runtime left side: the first frame shows the fallback.
class PlayerBadge extends StatelessWidget {
  const PlayerBadge({super.key, this.mark});

  final String? mark;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(Player.circle.symbol),
        Text(mark ?? '-'),
        Text(_lookup() ?? 'none'),
      ],
    );
  }

  String? _lookup() => DateTime.now().second.isEven ? mark : null;
}
