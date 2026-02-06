import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/appointment_note.dart';
import '../providers/appointment_provider.dart';

class AppointmentsScreen extends ConsumerWidget {
  const AppointmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appointmentsAsync = ref.watch(appointmentsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => Scaffold.of(context).openDrawer(),
          tooltip: 'Open menu',
        ),
        title: const Text('Appointments'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAppointmentForm(context, ref),
            tooltip: 'Add appointment',
          ),
        ],
      ),
      body: appointmentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (appointments) {
          final sorted = List<AppointmentNote>.from(appointments)
            ..sort((a, b) => b.date.compareTo(a.date));
          if (sorted.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('No appointments'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _showAppointmentForm(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('Add appointment'),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sorted.length,
            itemBuilder: (context, i) {
              final a = sorted[i];
              final dateStr = '${a.date.year}-${a.date.month.toString().padLeft(2, '0')}-${a.date.day.toString().padLeft(2, '0')}';
              return Dismissible(
                key: Key(a.id),
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
                      title: const Text('Delete appointment?'),
                      content: Text(
                        'Delete appointment at ${a.doctorOffice} on $dateStr?',
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
                },
                onDismissed: (_) {
                  ref.read(appointmentsProvider.notifier).delete(a.id);
                },
                child: Card(
                  child: ListTile(
                    leading: const Icon(Icons.event_note),
                    title: Text(a.doctorOffice),
                    subtitle: Text(
                      '$dateStr\n${a.notes}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _confirmDelete(context, ref, a),
                          tooltip: 'Delete',
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: () => _showAppointmentForm(context, ref, existing: a),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAppointmentForm(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAppointmentForm(BuildContext context, WidgetRef ref,
      {AppointmentNote? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AppointmentForm(
        existing: existing,
        onSave: (a) async {
          if (existing != null) {
            await ref.read(appointmentsProvider.notifier).update(a);
          } else {
            await ref.read(appointmentsProvider.notifier).add(a);
          }
          if (ctx.mounted) Navigator.pop(ctx);
        },
        onDelete: existing != null
            ? () async {
                await ref.read(appointmentsProvider.notifier).delete(existing!.id);
                if (ctx.mounted) Navigator.pop(ctx);
              }
            : null,
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, AppointmentNote a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete appointment?'),
        content: Text(
          'Delete appointment at ${a.doctorOffice}?',
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
      await ref.read(appointmentsProvider.notifier).delete(a.id);
    }
  }
}

class _AppointmentForm extends StatefulWidget {
  const _AppointmentForm({this.existing, required this.onSave, this.onDelete});

  final AppointmentNote? existing;
  final ValueChanged<AppointmentNote> onSave;
  final VoidCallback? onDelete;

  @override
  State<_AppointmentForm> createState() => _AppointmentFormState();
}

class _AppointmentFormState extends State<_AppointmentForm> {
  late DateTime _date;
  final _officeController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _date = widget.existing?.date ?? DateTime.now();
    _officeController.text = widget.existing?.doctorOffice ?? '';
    _notesController.text = widget.existing?.notes ?? '';
  }

  @override
  void dispose() {
    _officeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Appointment note',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('Date'),
              subtitle: Text(
                  '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}'),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                );
                if (d != null) setState(() => _date = d);
              },
            ),
            TextField(
              controller: _officeController,
              decoration: const InputDecoration(labelText: "Doctor's office"),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLines: 4,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                if (widget.onDelete != null) ...[
                  OutlinedButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete appointment?'),
                          content: const Text('This cannot be undone.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                widget.onDelete!();
                              },
                              style: FilledButton.styleFrom(backgroundColor: Colors.red),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('Delete'),
                  ),
                  const SizedBox(width: 16),
                ],
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      final office = _officeController.text.trim();
                      if (office.isEmpty) return;
                      widget.onSave(AppointmentNote(
                        id: widget.existing?.id ??
                            DateTime.now().millisecondsSinceEpoch.toString(),
                        date: _date,
                        doctorOffice: office,
                        notes: _notesController.text.trim(),
                      ));
                    },
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
