import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/flare_up.dart';
import '../providers/flare_up_provider.dart';
import '../widgets/log_flare_up_sheet.dart';

class FlareUpsScreen extends ConsumerWidget {
  const FlareUpsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flareUpsAsync = ref.watch(flareUpsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => Scaffold.of(context).openDrawer(),
          tooltip: 'Open menu',
        ),
        title: const Text('Flare-ups'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddFlareUp(context, ref),
            tooltip: 'Add flare-up',
          ),
        ],
      ),
      body: flareUpsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (flareUps) {
          final sorted = List<FlareUp>.from(flareUps)
            ..sort((a, b) => b.date.compareTo(a.date));
          if (sorted.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('No flare-ups recorded'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _showAddFlareUp(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('Add flare-up'),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sorted.length,
            itemBuilder: (context, i) {
              final f = sorted[i];
              return Dismissible(
                key: Key(f.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: Colors.red,
                  child: const Icon(Icons.delete, color: Colors.white, size: 32),
                ),
                confirmDismiss: (direction) async {
                  return await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete flare-up?'),
                      content: Text(
                        'Delete flare-up from ${_formatDate(f.date)}?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                },
                onDismissed: (_) {
                  ref.read(flareUpsProvider.notifier).delete(f.id);
                },
                child: Card(
                  child: ListTile(
                    leading: const Icon(Icons.warning_amber, color: Colors.orange),
                    title: Text(_formatDate(f.date)),
                    subtitle: Text(
                      '${f.leftEye ? "L" : ""}${f.rightEye ? "R" : ""} '
                      '${f.reason ?? ""} ${f.comment ?? ""}'.trim(),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showAddFlareUp(context, ref, existing: f),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddFlareUp(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  void _showAddFlareUp(BuildContext context, WidgetRef ref,
      {FlareUp? existing}) {
    showLogFlareUpSheet(context, ref, existing: existing);
  }
}
