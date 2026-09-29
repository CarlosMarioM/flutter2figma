import 'package:flutter/material.dart';

/// Patterns found in real apps while validating against them: an early
/// return for a loading state, a builder widget, loops, a switch expression,
/// a text field and a full-width button.
/// A route wrapper, like the provider/bloc wrappers real apps put around
/// screens. It reaches a Scaffold only through [SettingsScreen], so it is
/// not a screen of its own.
class SettingsRoute extends StatelessWidget {
  const SettingsRoute({super.key});

  @override
  Widget build(BuildContext context) {
    return Builder(builder: (context) => const SettingsScreen());
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

enum SyncState { idle, syncing, failed }

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = false;
  final _sync = ValueNotifier(SyncState.idle);
  final _toggles = const ['Notifications', 'Dark mode', 'Autoplay'];

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const TextField(
            decoration: InputDecoration(
              labelText: 'Display name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          for (final toggle in _toggles)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(toggle),
            ),
          ...['Privacy', 'About'].map((label) => Text(label)),
          ValueListenableBuilder(
            valueListenable: _sync,
            builder: (context, state, _) => switch (state) {
              SyncState.syncing => const LinearProgressIndicator(),
              SyncState.failed => const Text('Sync failed'),
              SyncState.idle => const Text('Up to date'),
            },
          ),
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
            ),
            onPressed: () => setState(() => _loading = true),
            child: const Text('Save changes'),
          ),
        ],
      ),
    );
  }
}
