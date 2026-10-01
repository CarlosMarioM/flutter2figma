import 'package:flutter/material.dart';

/// A second screen that exercises rows, flex, theme lookups and
/// project-local widgets with constructor parameters.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Text('Ada Lovelace', style: textTheme.headlineMedium),
            Text(
              'Analyst & programmer',
              style: textTheme.bodyLarge?.copyWith(color: Colors.grey),
            ),
            const Row(
              children: [
                Expanded(child: StatCard(label: 'Posts', value: '128')),
                SizedBox(width: 12),
                Expanded(child: StatCard(label: 'Followers', value: '4.2k')),
              ],
            ),
            Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    image: DecorationImage(
                      image: AssetImage('assets/avatar.png'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const Spacer(),
                // Sized by the 2.0x variant: 96 px → 48 logical pixels.
                Image.asset('assets/logo.png'),
              ],
            ),
            const Spacer(),
            _actions(primary: 'Save'),
          ],
        ),
      ),
    );
  }

  Widget _actions({required String primary}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(onPressed: () {}, child: const Text('Cancel')),
        const SizedBox(width: 8),
        FilledButton(onPressed: () {}, child: Text(primary)),
      ],
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            Text(label, style: TextStyle(color: Color(0xFF79747E))),
          ],
        ),
      ),
    );
  }
}
