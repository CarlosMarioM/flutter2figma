import 'package:flutter/material.dart';

import '../data.dart';
import '../widgets/common.dart';

/// Analytics: KPI cards, a painted line chart, goals and recent activity.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Overview'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: PersonAvatar(person: people[0], size: 32),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: _Kpi(
                  label: 'Revenue',
                  value: '\$48.2k',
                  delta: '+12.4%',
                  icon: Icons.payments_outlined,
                  color: scheme.primaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Kpi(
                  label: 'Orders',
                  value: '1,284',
                  delta: '+3.1%',
                  icon: Icons.shopping_cart_outlined,
                  color: scheme.tertiaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            color: scheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Weekly sales', style: theme.textTheme.titleMedium),
                      const Spacer(),
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 0, label: Text('W')),
                          ButtonSegment(value: 1, label: Text('M')),
                          ButtonSegment(value: 2, label: Text('Y')),
                        ],
                        selected: const {0},
                        showSelectedIcon: false,
                        onSelectionChanged: (_) {},
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 160,
                    child: CustomPaint(
                      painter: _LineChartPainter(
                        values: const [12, 18, 15, 24, 21, 30, 27],
                        line: scheme.primary,
                        fill: scheme.primary.withValues(alpha: 0.12),
                        grid: scheme.outlineVariant,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final d in [
                        'Mon',
                        'Tue',
                        'Wed',
                        'Thu',
                        'Fri',
                        'Sat',
                        'Sun',
                      ])
                        Text(d, style: theme.textTheme.labelSmall),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: scheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CircularProgressIndicator(
                          value: 0.72,
                          strokeWidth: 8,
                          backgroundColor: scheme.surfaceContainerHighest,
                        ),
                        Center(
                          child: Text(
                            '72%',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Monthly goal',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '\$34.7k of \$48k',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 10),
                        LinearProgressIndicator(
                          value: 0.45,
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SectionHeader(title: 'Recent activity'),
          for (final (i, p) in people.indexed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: PersonAvatar(person: p, online: i.isEven),
              title: Text(p.name),
              subtitle: Text(
                [
                  'Placed order #10${42 + i}',
                  'Left a 5★ review',
                  'Requested a refund',
                  'Joined the team',
                ][i],
              ),
              trailing: Text(
                '${(i + 1) * 7}m',
                style: theme.textTheme.labelSmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.label,
    required this.value,
    required this.delta,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String delta;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(height: 12),
          Text(label, style: theme.textTheme.labelLarge),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.trending_up, size: 16, color: Color(0xFF2E7D32)),
              const SizedBox(width: 4),
              Text(
                delta,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: const Color(0xFF2E7D32),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.values,
    required this.line,
    required this.fill,
    required this.grid,
  });

  final List<double> values;
  final Color line;
  final Color fill;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final max = values.reduce((a, b) => a > b ? a : b) * 1.15;
    final points = [
      for (var i = 0; i < values.length; i++)
        Offset(
          size.width * i / (values.length - 1),
          size.height * (1 - values[i] / max),
        ),
    ];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i];
      final mid = (a.dx + b.dx) / 2;
      path.cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
    }
    final area = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    for (final p in points) {
      canvas.drawCircle(p, 4, Paint()..color = line);
      canvas.drawCircle(p, 2, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_LineChartPainter old) => old.values != values;
}
