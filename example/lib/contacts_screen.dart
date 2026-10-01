import 'package:flutter/material.dart';

/// List tiles, chips and a navigation bar, with Material 3 defaults.
class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contacts')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                const Chip(avatar: Icon(Icons.person), label: Text('Friends')),
                FilterChip(
                  label: const Text('Work'),
                  selected: true,
                  onSelected: (_) {},
                ),
                InputChip(label: const Text('Ada'), onDeleted: () {}),
              ],
            ),
          ),
          const ListTile(
            leading: Icon(Icons.person),
            title: Text('Ada Lovelace'),
            trailing: Icon(Icons.chevron_right),
          ),
          const ListTile(
            leading: Icon(Icons.person),
            title: Text('Grace Hopper'),
            subtitle: Text('Compilers'),
          ),
          SwitchListTile(
            title: const Text('Favorites only'),
            value: true,
            onChanged: (_) {},
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 1,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.people), label: 'Contacts'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
