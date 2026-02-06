import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/flare_up.dart';
import '../providers/flare_up_provider.dart';

const _reasons = [
  'sick',
  'lack of sleep',
  'too much sun',
  'screens/pictures',
  'stress',
  'allergies',
  'other',
];

void showLogFlareUpSheet(BuildContext context, WidgetRef ref, {FlareUp? existing}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => LogFlareUpForm(
      existing: existing,
      reasons: _reasons,
      onSave: (f) async {
        if (existing != null) {
          await ref.read(flareUpsProvider.notifier).update(f);
        } else {
          await ref.read(flareUpsProvider.notifier).add(f);
        }
        if (ctx.mounted) Navigator.pop(ctx);
      },
      onDelete: existing != null
          ? () async {
              await ref.read(flareUpsProvider.notifier).delete(existing!.id);
              if (ctx.mounted) Navigator.pop(ctx);
            }
          : null,
    ),
  );
}

class LogFlareUpForm extends StatefulWidget {
  const LogFlareUpForm({
    super.key,
    this.existing,
    required this.reasons,
    required this.onSave,
    this.onDelete,
  });

  final FlareUp? existing;
  final List<String> reasons;
  final ValueChanged<FlareUp> onSave;
  final VoidCallback? onDelete;

  @override
  State<LogFlareUpForm> createState() => _LogFlareUpFormState();
}

class _LogFlareUpFormState extends State<LogFlareUpForm> {
  late DateTime _date;
  PainLevel? _leftPain;
  PainLevel? _rightPain;
  String? _reason;
  final _commentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _date = widget.existing?.date ?? DateTime.now();
    _leftPain = widget.existing?.leftEye == true
        ? (widget.existing?.leftPainLevel ?? PainLevel.low)
        : null;
    _rightPain = widget.existing?.rightEye == true
        ? (widget.existing?.rightPainLevel ?? PainLevel.low)
        : null;
    _reason = widget.existing?.reason;
    _commentController.text = widget.existing?.comment ?? '';
  }

  @override
  void dispose() {
    _commentController.dispose();
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
            Text('Log flare-up', style: Theme.of(context).textTheme.titleLarge),
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
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (d != null) setState(() => _date = d);
              },
            ),
            _PainEyeRow(
              label: 'Left eye',
              selected: _leftPain,
              onSelected: (p) => setState(() => _leftPain = p),
              flip: true,
            ),
            const SizedBox(height: 12),
            _PainEyeRow(
              label: 'Right eye',
              selected: _rightPain,
              onSelected: (p) => setState(() => _rightPain = p),
              flip: false,
            ),
            DropdownButtonFormField<String>(
              value: _reason,
              decoration: const InputDecoration(labelText: 'Reason'),
              items: widget.reasons
                  .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                  .toList(),
              onChanged: (r) => setState(() => _reason = r),
            ),
            TextField(
              controller: _commentController,
              decoration: const InputDecoration(labelText: 'Comment'),
              maxLines: 2,
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
                          title: const Text('Delete flare-up?'),
                          content: const Text(
                            'This cannot be undone.',
                          ),
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
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.red,
                              ),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                    child: const Text('Delete'),
                  ),
                  const SizedBox(width: 16),
                ],
                Expanded(
                  child: FilledButton(
                    onPressed: (_leftPain != null || _rightPain != null)
                        ? () {
                            widget.onSave(FlareUp(
                              id: widget.existing?.id ??
                                  DateTime.now().millisecondsSinceEpoch.toString(),
                              date: _date,
                              leftEye: _leftPain != null,
                              rightEye: _rightPain != null,
                              leftPainLevel: _leftPain,
                              rightPainLevel: _rightPain,
                              reason: _reason,
                              comment: _commentController.text.trim().isEmpty
                                  ? null
                                  : _commentController.text.trim(),
                            ));
                          }
                        : null,
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

/// Pain levels ordered from least to most severe (left to right).
const _painLevelOrder = [
  PainLevel.low,
  PainLevel.medium,
  PainLevel.bad,
  PainLevel.terrible,
];

class _PainEyeRow extends StatelessWidget {
  const _PainEyeRow({
    required this.label,
    required this.selected,
    required this.onSelected,
    required this.flip,
  });

  final String label;
  final PainLevel? selected;
  final ValueChanged<PainLevel?> onSelected;
  final bool flip;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _PainEyeChip(
                level: null,
                label: 'none',
                isSelected: selected == null,
                flip: flip,
                onTap: () => onSelected(null),
              ),
            ),
            ..._painLevelOrder.map((level) => Expanded(
                  child: _PainEyeChip(
                    level: level,
                    label: level.name,
                    isSelected: selected == level,
                    flip: flip,
                    onTap: () => onSelected(level),
                  ),
                )),
          ],
        ),
      ],
    );
  }
}

class _PainEyeChip extends StatelessWidget {
  const _PainEyeChip({
    required this.level,
    required this.label,
    required this.isSelected,
    required this.flip,
    required this.onTap,
  });

  final PainLevel? level;
  final String label;
  final bool isSelected;
  final bool flip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = painLevelColor(level);
    final opacity = level == null ? 0.25 : 1.0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: opacity,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()..scale(flip ? -1.0 : 1.0, 1.0),
                child: SvgPicture.asset(
                  'assets/icons/eye.svg',
                  width: 28,
                  height: 28,
                  colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
