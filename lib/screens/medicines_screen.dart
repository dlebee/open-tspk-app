import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/medicine.dart';
import '../providers/medicine_provider.dart';
import 'medicine_detail_screen.dart';

class MedicinesScreen extends ConsumerWidget {
  const MedicinesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final medicinesAsync = ref.watch(medicinesProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => Scaffold.of(context).openDrawer(),
          tooltip: 'Open menu',
        ),
        title: const Text('Medicines'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _navigateToDetail(context, ref, null),
            tooltip: 'Add medicine',
          ),
        ],
      ),
      body: medicinesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (medicines) {
          if (medicines.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('No medicines yet'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _navigateToDetail(context, ref, null),
                    icon: const Icon(Icons.add),
                    label: const Text('Add medicine'),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: medicines.length,
            itemBuilder: (context, i) {
              final m = medicines[i];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.medication),
                  title: Text(m.name),
                  subtitle: Text('${m.schedules.length} schedule(s)'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _confirmDelete(context, ref, m),
                        tooltip: 'Delete',
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: () => _navigateToDetail(context, ref, m),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToDetail(context, ref, null),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _navigateToDetail(BuildContext context, WidgetRef ref, Medicine? medicine) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => MedicineDetailScreen(
          medicine: medicine,
          onSaved: () => Navigator.pop(ctx, true),
        ),
      ),
    ).then((_) => ref.invalidate(medicinesProvider));
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Medicine m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete medicine?'),
        content: Text(
          'Delete "${m.name}"? This will remove the medicine and its schedules. Dose history is kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(medicinesProvider.notifier).delete(m.id);
    }
  }
}
