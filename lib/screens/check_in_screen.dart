import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/flare_up.dart';
import '../providers/flare_up_provider.dart';
import '../theme/dusk_theme.dart';
import '../ui/dusk_ui.dart';

const checkInSymptoms = [
  'Light hurts',
  'Watery',
  'Blurry',
  'Something in it',
  'Itchy',
  'Red',
  'Dry',
];

/// "How do your eyes feel?" — stored as a [FlareUp] record.
class CheckInScreen extends ConsumerStatefulWidget {
  const CheckInScreen({super.key, this.existing});

  final FlareUp? existing;

  @override
  ConsumerState<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends ConsumerState<CheckInScreen> {
  late EyeFeel _left;
  late EyeFeel _right;
  late Set<String> _symptoms;
  late TextEditingController _note;
  late DateTime _date;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _left = e?.leftFeel ?? EyeFeel.calm;
    _right = e?.rightFeel ?? EyeFeel.calm;
    _symptoms = (e?.reason ?? '')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    _note = TextEditingController(text: e?.comment ?? '');
    _date = e?.date ?? DateTime.now();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final record = FlareUp(
      id: widget.existing?.id,
      date: _date,
      leftEye: _left != EyeFeel.calm,
      rightEye: _right != EyeFeel.calm,
      leftPainLevel: _left.painLevel,
      rightPainLevel: _right.painLevel,
      reason: _symptoms.isEmpty ? null : _symptoms.join(', '),
      comment: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
    final notifier = ref.read(flareUpsProvider.notifier);
    if (widget.existing == null) {
      await notifier.add(record);
    } else {
      await notifier.update(record);
    }
    if (!mounted) return;
    Navigator.pop(context);
    showDuskSnack(context, record.isFlare ? 'Saved as a flare-up' : 'Check-in saved');
  }

  Future<void> _delete() async {
    await ref.read(flareUpsProvider.notifier).delete(widget.existing!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final extraSymptoms = _symptoms.where((s) => !checkInSymptoms.contains(s));
    return DuskPage(
      title: 'How do your\neyes feel?',
      leadingIcon: Icons.close,
      actions: [
        if (widget.existing != null)
          TextButton(
            onPressed: _delete,
            style: TextButton.styleFrom(foregroundColor: Dusk.rose),
            child: const Text('Delete'),
          )
        else
          Text(hm(_date), style: const TextStyle(color: Dusk.textSecondary)),
      ],
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_left.isFlare || _right.isFlare)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Sore or flaring shows up as a flare-up on your Journey.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Dusk.textSecondary, fontSize: 13),
              ),
            ),
          PrimaryButton(label: 'Save check-in', onPressed: _saving ? null : _save),
        ],
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _EyeColumn(
                label: 'LEFT',
                value: _left,
                onChanged: (v) => setState(() => _left = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _EyeColumn(
                label: 'RIGHT',
                value: _right,
                onChanged: (v) => setState(() => _right = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const SectionLabel('Anything else?'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in [...checkInSymptoms, ...extraSymptoms])
              FilterChip(
                label: Text(s),
                selected: _symptoms.contains(s),
                showCheckmark: false,
                selectedColor: Dusk.amberSoft,
                backgroundColor: Colors.transparent,
                side: BorderSide(color: _symptoms.contains(s) ? Dusk.amber : Dusk.border),
                labelStyle: TextStyle(color: _symptoms.contains(s) ? Dusk.amber : Dusk.textSecondary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                onSelected: (on) => setState(() => on ? _symptoms.add(s) : _symptoms.remove(s)),
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _note,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'A note, if you want (screen day, allergies…)'),
        ),
      ],
    );
  }
}

class _EyeColumn extends StatelessWidget {
  const _EyeColumn({required this.label, required this.value, required this.onChanged});

  final String label;
  final EyeFeel value;
  final ValueChanged<EyeFeel> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
            color: Dusk.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        for (final f in EyeFeel.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Semantics(
              selected: f == value,
              label: '$label eye ${f.label}',
              child: Material(
                color: f == value ? f.bg : Dusk.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: f == value ? BorderSide(color: f.fg, width: 2) : BorderSide.none,
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => onChanged(f),
                  child: SizedBox(
                    height: 56,
                    child: Center(
                      child: Text(
                        f.label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: f == value ? FontWeight.w600 : FontWeight.w500,
                          color: f == value ? f.fg : Dusk.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
