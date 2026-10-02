import 'package:flutter/material.dart';

import '../data.dart';

/// Tabs over a list of media rows with progress, plus a mini player.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Library'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Podcasts'),
              Tab(text: 'Audiobooks'),
              Tab(text: 'Downloads'),
            ],
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: TabBarView(
                children: [
                  ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: products.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 88),
                    itemBuilder: (context, i) {
                      final p = products[i];
                      return ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.asset(
                            p.image,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                          ),
                        ),
                        title: Text('Episode ${i + 12}: ${p.name}'),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: LinearProgressIndicator(value: (i + 1) / 7),
                        ),
                        trailing: IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.play_circle_fill),
                          iconSize: 36,
                          color: scheme.primary,
                        ),
                      );
                    },
                  ),
                  const Center(child: Text('No audiobooks yet')),
                  const Center(child: Text('Nothing downloaded')),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(
                      products[3].image,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Design Matters',
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(
                          'Episode 14 · 32 min left',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(onPressed: () {}, icon: const Icon(Icons.pause)),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.skip_next),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
