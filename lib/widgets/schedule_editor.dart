import 'package:flutter/material.dart';

import '../models/medicine.dart';
import '../models/medicine_schedule.dart';

class ScheduleEditor extends StatelessWidget {
  const ScheduleEditor({
    super.key,
    required this.schedules,
    required this.onChanged,
  });

  final List<MedicineSchedule> schedules;
  final ValueChanged<List<MedicineSchedule>> onChanged;

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...List.generate(schedules.length, (i) {
          return _ScheduleCard(
            schedule: schedules[i],
            onChanged: (s) {
              final updated = schedules.toList();
              updated[i] = s;
              onChanged(updated);
            },
            onRemove: () {
              final updated = schedules.toList()..removeAt(i);
              onChanged(updated);
            },
            canRemove: schedules.length > 1,
          );
        }),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () {
            onChanged([
              ...schedules,
              MedicineSchedule(
                eye: Eye.both,
                daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
                times: ['21:00'],
              ),
            ]);
          },
          icon: const Icon(Icons.add),
          label: const Text('Add schedule'),
        ),
      ],
    );
  }
}

class _ScheduleCard extends StatefulWidget {
  const _ScheduleCard({
    required this.schedule,
    required this.onChanged,
    required this.onRemove,
    required this.canRemove,
  });

  final MedicineSchedule schedule;
  final ValueChanged<MedicineSchedule> onChanged;
  final VoidCallback onRemove;
  final bool canRemove;

  @override
  State<_ScheduleCard> createState() => _ScheduleCardState();
}

class _ScheduleCardState extends State<_ScheduleCard> {
  late List<int> _daysOfWeek;
  late List<String> _times;

  @override
  void initState() {
    super.initState();
    _daysOfWeek = widget.schedule.daysOfWeek.toList();
    _times = widget.schedule.times.toList();
  }

  @override
  void didUpdateWidget(_ScheduleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.schedule != widget.schedule) {
      _daysOfWeek = widget.schedule.daysOfWeek.toList();
      _times = widget.schedule.times.toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Where', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<Eye>(
                    segments: const [
                      ButtonSegment(value: Eye.left, label: Text('Left')),
                      ButtonSegment(value: Eye.right, label: Text('Right')),
                      ButtonSegment(value: Eye.both, label: Text('Both')),
                      ButtonSegment(value: Eye.other, label: Text('Other (e.g. pill)')),
                    ],
                    selected: {widget.schedule.eye},
                    onSelectionChanged: (s) => _emit(eye: s.first),
                  ),
                ),
                if (widget.canRemove)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: widget.onRemove,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 4,
              children: List.generate(7, (i) {
                final day = i + 1;
                final selected = _daysOfWeek.contains(day);
                return FilterChip(
                  label: Text(ScheduleEditor._days[i]),
                  selected: selected,
                  onSelected: (v) {
                    setState(() {
                      if (v) {
                        _daysOfWeek.add(day);
                      } else {
                        _daysOfWeek.remove(day);
                      }
                      _daysOfWeek.sort();
                      _emit(daysOfWeek: _daysOfWeek);
                    });
                  },
                );
              }),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ..._times.map((t) => Chip(
                      label: Text(t),
                      onDeleted: () {
                        setState(() {
                          _times.remove(t);
                          _emit(times: _times);
                        });
                      },
                    )),
                ActionChip(
                  label: const Text('+ Time'),
                  onPressed: () async {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.now(),
                    );
                    if (time != null) {
                      final str =
                          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                      if (!_times.contains(str)) {
                        setState(() {
                          _times.add(str);
                          _times.sort();
                          _emit(times: _times);
                        });
                      }
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _emit({
    Eye? eye,
    List<int>? daysOfWeek,
    List<String>? times,
  }) {
    widget.onChanged(widget.schedule.copyWith(
      eye: eye,
      daysOfWeek: daysOfWeek ?? _daysOfWeek,
      times: times ?? _times,
    ));
  }
}
