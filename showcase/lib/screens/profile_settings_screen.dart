import 'package:flutter/material.dart';

import '../data.dart';

/// A profile header over a gradient cover, stats, then grouped settings.
class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  bool _notifications = true;
  bool _darkMode = false;
  double _textSize = 0.4;
  String _units = 'metric';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final me = people[2];
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          SizedBox(
            height: 230,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  height: 160,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [scheme.primary, scheme.tertiary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: IconButton(
                    onPressed: () {},
                    icon: Icon(
                      Icons.settings_outlined,
                      color: scheme.onPrimary,
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  top: 110,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      shape: BoxShape.circle,
                    ),
                    child: CircleAvatar(
                      radius: 44,
                      backgroundImage: AssetImage(me.avatar),
                    ),
                  ),
                ),
                Positioned(
                  left: 128,
                  top: 172,
                  right: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(me.name, style: theme.textTheme.titleLarge),
                      Text(
                        me.role,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                for (final (label, value) in [
                  ('Orders', '38'),
                  ('Reviews', '12'),
                  ('Points', '2.4k'),
                ])
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          value,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(label, style: theme.textTheme.labelMedium),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Divider(),
          _Group('Preferences', [
            SwitchListTile(
              secondary: const Icon(Icons.notifications_outlined),
              title: const Text('Notifications'),
              subtitle: const Text('Orders, offers and reminders'),
              value: _notifications,
              onChanged: (v) => setState(() => _notifications = v),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.dark_mode_outlined),
              title: const Text('Dark mode'),
              value: _darkMode,
              onChanged: (v) => setState(() => _darkMode = v),
            ),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: const Text('Text size'),
              subtitle: Slider(
                value: _textSize,
                onChanged: (v) => setState(() => _textSize = v),
              ),
            ),
          ]),
          RadioGroup<String>(
            groupValue: _units,
            onChanged: (v) => setState(() => _units = v!),
            child: const _Group('Units', [
              RadioListTile<String>(
                title: Text('Metric (kg, km)'),
                value: 'metric',
              ),
              RadioListTile<String>(
                title: Text('Imperial (lb, mi)'),
                value: 'imperial',
              ),
            ]),
          ),
          _Group('Account', [
            const ListTile(
              leading: Icon(Icons.location_on_outlined),
              title: Text('Addresses'),
              trailing: Icon(Icons.chevron_right),
            ),
            const ListTile(
              leading: Icon(Icons.credit_card),
              title: Text('Payment methods'),
              subtitle: Text('Visa •••• 4242'),
              trailing: Icon(Icons.chevron_right),
            ),
            ListTile(
              leading: Icon(Icons.logout, color: scheme.error),
              title: Text('Sign out', style: TextStyle(color: scheme.error)),
            ),
          ]),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group(this.title, this.children);

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          Card(
            color: theme.colorScheme.surfaceContainerLow,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}
