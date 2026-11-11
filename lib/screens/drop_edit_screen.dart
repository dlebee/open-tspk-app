import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/medicine.dart';
import '../models/medicine_schedule.dart';
import '../providers/dose_provider.dart';
import '../providers/medicine_provider.dart';
import '../theme/dusk_theme.dart';
import '../ui/dusk_ui.dart';

class DropEditScreen extends ConsumerStatefulWidget {
  const DropEditScreen({super.key, this.medicine});

  final Medicine? medicine;

  @override
  ConsumerState<DropEditScreen> createState() => _DropEditScreenState();
}

class _DropEditScreenState extends ConsumerState<DropEditScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.medicine?.name ?? '');
  late List<MedicineSchedule> _schedules = widget.medicine?.schedules.toList() ??
      [MedicineSchedule(eye: Eye.both, daysOfWeek: const [1, 2, 3, 4, 5, 6, 7], times: const ['08:00'])];
  String? _error;
  bool _saving = false;

  bool get _isNew => widget.medicine == null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give it a name');
      return;
    }
    if (_schedules.any((s) => s.times.isEmpty || s.daysOfWeek.isEmpty)) {
      setState(() => _error = 'Each schedule needs at least one time and one day');
      return;
    }
    setState(() => _saving = true);
    final notifier = ref.read(medicinesProvider.notifier);
    if (_isNew) {
      await notifier.add(Medicine(name: name, schedules: _schedules, createdAt: DateTime.now()));
    } else {
      await notifier.update(widget.medicine!.copyWith(name: name, schedules: _schedules));
      await ref.read(dosesProvider.notifier).refresh();
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${widget.medicine!.name}?'),
        content: const Text('Its reminders stop. Drops you already logged stay in your history.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Dusk.rose),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(medicinesProvider.notifier).delete(widget.medicine!.id);
    if (mounted) Navigator.pop(context);
  }

  void _setSchedule(int i, MedicineSchedule s) => setState(() {
        _schedules = [..._schedules]..[i] = s;
        _error = null;
      });

  @override
  Widget build(BuildContext context) {
    return DuskPage(
      title: _isNew ? 'Add a drop' : 'Edit drop',
      leadingIcon: Icons.close,
      actions: [
        if (!_isNew)
          TextButton(
            onPressed: _delete,
            style: TextButton.styleFrom(foregroundColor: Dusk.rose),
            child: const Text('Delete'),
          ),
      ],
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(_error!, style: const TextStyle(color: Dusk.rose)),
            ),
          PrimaryButton(label: 'Save', onPressed: _saving ? null : _save),
        ],
      ),
      children: [
        const SectionLabel('Name'),
        TextField(
          controller: _name,
          autocorrect: false,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          decoration: const InputDecoration(hintText: 'Steroid drop'),
          onChanged: (_) => setState(() => _error = null),
        ),
        const SizedBox(height: 20),
        for (var i = 0; i < _schedules.length; i++) ...[
          _ScheduleCard(
            schedule: _schedules[i],
            index: i,
            canRemove: _schedules.length > 1,
            onChanged: (s) => _setSchedule(i, s),
            onRemove: () => setState(() => _schedules = [..._schedules]..removeAt(i)),
          ),
          const SizedBox(height: 12),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _schedules = [
                  ..._schedules,
                  MedicineSchedule(eye: Eye.right, daysOfWeek: const [1, 2, 3, 4, 5, 6, 7], times: const ['20:00']),
                ]),
            icon: const Icon(Icons.add),
            label: const Text('Add a different schedule'),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(left: 12),
          child: Text(
            'For example, the right eye only, or a different time on weekends.',
            style: TextStyle(fontSize: 13, color: Dusk.textMuted),
          ),
        ),
      ],
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({
    required this.schedule,
    required this.index,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  final MedicineSchedule schedule;
  final int index;
  final bool canRemove;
  final ValueChanged<MedicineSchedule> onChanged;
  final VoidCallback onRemove;

  static const _days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  Future<void> _addTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 12, minute: 0),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    final t = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    if (schedule.times.contains(t)) return;
    onChanged(schedule.copyWith(times: [...schedule.times, t]..sort()));
  }

  @override
  Widget build(BuildContext context) {
    final everyDay = schedule.daysOfWeek.length == 7;
    final sortedTimes = [...schedule.times]..sort();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Dusk.surface, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  index == 0 ? 'WHERE IT GOES' : 'SCHEDULE ${index + 1}',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1, color: Dusk.textSecondary),
                ),
              ),
              if (canRemove)
                IconButton(
                  onPressed: onRemove,
                  tooltip: 'Remove schedule',
                  icon: const Icon(Icons.delete_outline, color: Dusk.textMuted, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedButton<Eye>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: Eye.left, label: Text('Left')),
              ButtonSegment(value: Eye.right, label: Text('Right')),
              ButtonSegment(value: Eye.both, label: Text('Both')),
              ButtonSegment(value: Eye.other, label: Text('Pill')),
            ],
            selected: {schedule.eye},
            onSelectionChanged: (s) => onChanged(schedule.copyWith(eye: s.first)),
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith(
                  (s) => s.contains(WidgetState.selected) ? Dusk.amberSoft : Colors.transparent),
              foregroundColor: WidgetStateProperty.resolveWith(
                  (s) => s.contains(WidgetState.selected) ? Dusk.amber : Dusk.textSecondary),
              side: const WidgetStatePropertyAll(BorderSide(color: Dusk.border)),
            ),
          ),
          const SizedBox(height: 18),
          const Text('WHEN',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1, color: Dusk.textSecondary)),
          const SizedBox(height: 10),
          _DayBar(times: sortedTimes),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in sortedTimes)
                InputChip(
                  label: Text(t, style: const TextStyle(fontWeight: FontWeight.w600, color: Dusk.amber)),
                  backgroundColor: Dusk.amberSoft,
                  side: BorderSide.none,
                  deleteIconColor: Dusk.amber,
                  onDeleted: () => onChanged(schedule.copyWith(times: schedule.times.where((x) => x != t).toList())),
                  deleteButtonTooltipMessage: 'Remove $t',
                ),
              ActionChip(
                label: const Text('+ Time'),
                backgroundColor: Colors.transparent,
                side: const BorderSide(color: Dusk.border),
                onPressed: () => _addTime(context),
              ),
            ],
          ),
          const Divider(height: 32),
          Row(
            children: [
              const Expanded(child: Text('Every day', style: TextStyle(fontSize: 15, color: Dusk.text))),
              Switch(
                value: everyDay,
                onChanged: (on) => onChanged(schedule.copyWith(
                    daysOfWeek: on ? const [1, 2, 3, 4, 5, 6, 7] : const [1, 2, 3, 4, 5])),
              ),
            ],
          ),
          if (!everyDay) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var d = 1; d <= 7; d++)
                  Semantics(
                    label: _dayNames[d - 1],
                    selected: schedule.daysOfWeek.contains(d),
                    button: true,
                    excludeSemantics: true,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        final days = {...schedule.daysOfWeek};
                        days.contains(d) ? days.remove(d) : days.add(d);
                        onChanged(schedule.copyWith(daysOfWeek: days.toList()..sort()));
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: schedule.daysOfWeek.contains(d) ? Dusk.amberSoft : Dusk.surfaceHigh,
                        ),
                        child: Text(
                          _days[d - 1],
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: schedule.daysOfWeek.contains(d) ? Dusk.amber : Dusk.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A 24-hour bar with a dot for each time.
class _DayBar extends StatelessWidget {
  const _DayBar({required this.times});

  final List<String> times;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, c) => SizedBox(
              height: 22,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 9,
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(color: Dusk.surfaceHigh, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  for (final t in times)
                    Positioned(
                      left: (c.maxWidth - 18) * _fraction(t),
                      top: 2,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: const BoxDecoration(color: Dusk.amber, shape: BoxShape.circle),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final l in const ['00', '06', '12', '18', '24'])
                Text(l, style: const TextStyle(fontSize: 11, color: Dusk.textMuted)),
            ],
          ),
        ],
      ),
    );
  }

  double _fraction(String t) {
    final p = t.split(':');
    final minutes = (int.tryParse(p[0]) ?? 0) * 60 + (p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
    return minutes / (24 * 60);
  }
}
