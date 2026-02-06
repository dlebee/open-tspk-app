import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/activity_item.dart';
import '../models/medicine_dose.dart';
import '../widgets/flare_up_emojis.dart';
import '../providers/activity_provider.dart';
import '../widgets/unscheduled_dose_dialog.dart';

class ActivityLogScreen extends ConsumerWidget {
  const ActivityLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activityAsync = ref.watch(activityLogProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => Scaffold.of(context).openDrawer(),
          tooltip: 'Open menu',
        ),
        title: const Text('Activity'),
      ),
      body: activityAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No activity yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Log doses, flare-ups, and appointments\nto see them here.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];
              return _ActivityTile(
                item: item,
                onTap: () => _onItemTap(context, ref, item),
              );
            },
          );
        },
      ),
    );
  }

  void _onItemTap(BuildContext context, WidgetRef ref, ActivityItem item) {
    switch (item.type) {
      case ActivityType.dose:
        if (item.dose != null) {
          showDialog(
            context: context,
            builder: (ctx) => UnscheduledDoseDialog(dose: item.dose!),
          );
        }
        break;
      case ActivityType.flareUp:
        // Could navigate to flare ups tab or show detail
        break;
      case ActivityType.appointment:
        // Could navigate to appointments tab or show detail
        break;
    }
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.item, required this.onTap});

  final ActivityItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (item.type) {
      ActivityType.dose => _getDoseIconAndColor(item.dose),
      ActivityType.flareUp => (Icons.warning_amber, Colors.orange),
      ActivityType.appointment => (Icons.event_note, Colors.blue),
    };

    final dateStr = DateFormat('MMM d, yyyy').format(item.date);
    final timeStr = DateFormat('HH:mm').format(item.date);
    final subtitle = item.subtitle != null
        ? '$dateStr at $timeStr\n${item.subtitle}'
        : '$dateStr at $timeStr';

    Widget leading;
    if (item.type == ActivityType.flareUp && item.flareUp != null) {
      leading = FlareUpEyes(flareUp: item.flareUp!, size: 22);
    } else {
      leading = CircleAvatar(
        backgroundColor: color.withOpacity(0.2),
        child: Icon(icon, color: color),
      );
    }

    return Card(
      child: ListTile(
        onTap: onTap,
        leading: leading,
        title: Text(item.title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  (IconData, Color) _getDoseIconAndColor(MedicineDose? dose) {
    if (dose != null && dose.status == DoseStatus.skipped) {
      return (Icons.arrow_forward, Colors.orange);
    }
    return (Icons.medication, Colors.green);
  }
}
