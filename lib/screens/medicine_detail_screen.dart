import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../navigation_keys.dart';
import '../models/medicine.dart';
import '../models/medicine_schedule.dart';
import '../providers/medicine_provider.dart';
import '../providers/dose_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/schedule_editor.dart';

class MedicineDetailScreen extends ConsumerStatefulWidget {
  const MedicineDetailScreen({super.key, this.medicine, this.onSaved});

  final Medicine? medicine;
  final VoidCallback? onSaved;

  @override
  ConsumerState<MedicineDetailScreen> createState() =>
      _MedicineDetailScreenState();
}

class _MedicineDetailScreenState extends ConsumerState<MedicineDetailScreen> {
  late TextEditingController _nameController;
  late List<MedicineSchedule> _schedules;
  late DateTime _startDate;
  bool _isNew = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _isNew = widget.medicine == null;
    _nameController = TextEditingController(text: widget.medicine?.name ?? '');
    _schedules = widget.medicine?.schedules.toList() ??
        [MedicineSchedule(eye: Eye.both, daysOfWeek: [1, 2, 3, 4, 5, 6, 7], times: ['21:00'])];
    _startDate = widget.medicine?.createdAt ?? DateTime.now();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Add medicine' : 'Edit medicine'),
        actions: [
          if (!_isNew)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => _confirmDelete(context),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Prednisolone',
            ),
          ),
          if (_isNew) ...[
            Consumer(
              builder: (context, ref, _) {
                final developerMode = ref.watch(developerModeProvider);
                if (!developerMode) return const SizedBox.shrink();
                return Column(
                  children: [
                    const SizedBox(height: 16),
                    ListTile(
                      title: const Text('Start date'),
                      subtitle: Text(DateFormat('MMM d, yyyy').format(_startDate)),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _startDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (date != null) {
                          setState(() => _startDate = date);
                        }
                      },
                    ),
                  ],
                );
              },
            ),
          ],
          const SizedBox(height: 24),
          Text('Schedules', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ScheduleEditor(
            schedules: _schedules,
            onChanged: (s) => setState(() => _schedules = s),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isNew ? 'Add' : 'Save'),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    if (_isSaving) return;

    setState(() => _isSaving = true);
    try {
      if (_isNew) {
        final medicine = Medicine(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: name,
          schedules: _schedules,
          createdAt: _startDate,
        );
        await ref.read(medicinesProvider.notifier).add(medicine);
      } else {
        final medicine = widget.medicine!.copyWith(
          name: name,
          schedules: _schedules,
        );
        await ref.read(medicinesProvider.notifier).update(medicine);
        // Invalidate doses provider to refresh after medicine name update
        ref.invalidate(dosesProvider);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save')),
        );
      }
      return;
    }
    if (!mounted) return;
    if (widget.onSaved != null) {
      widget.onSaved!();
    } else {
      navigatorKey.currentState?.pop(true);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete medicine?'),
        content: const Text(
          'This will remove the medicine and its schedules. Dose history is kept.',
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
    if (ok != true || widget.medicine == null || !mounted) return;
    final id = widget.medicine!.id;
    try {
      await ref.read(medicinesProvider.notifier).delete(id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete')),
        );
      }
      return;
    }
    if (!mounted) return;
    if (widget.onSaved != null) {
      widget.onSaved!();
    } else {
      navigatorKey.currentState?.pop(true);
    }
  }
}
