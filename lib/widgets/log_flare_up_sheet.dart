import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  bool _leftEye = false;
  bool _rightEye = false;
  PainLevel? _leftPain;
  PainLevel? _rightPain;
  String? _reason;
  final _commentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _date = widget.existing?.date ?? DateTime.now();
    _leftEye = widget.existing?.leftEye ?? false;
    _rightEye = widget.existing?.rightEye ?? false;
    _leftPain = widget.existing?.leftPainLevel;
    _rightPain = widget.existing?.rightPainLevel;
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
            CheckboxListTile(
              title: const Text('Left eye'),
              value: _leftEye,
              onChanged: (v) => setState(() => _leftEye = v ?? false),
            ),
            if (_leftEye)
              DropdownButtonFormField<PainLevel>(
                value: _leftPain,
                decoration: const InputDecoration(labelText: 'Left pain level'),
                items: PainLevel.values
                    .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
                    .toList(),
                onChanged: (p) => setState(() => _leftPain = p),
              ),
            CheckboxListTile(
              title: const Text('Right eye'),
              value: _rightEye,
              onChanged: (v) => setState(() => _rightEye = v ?? false),
            ),
            if (_rightEye)
              DropdownButtonFormField<PainLevel>(
                value: _rightPain,
                decoration: const InputDecoration(labelText: 'Right pain level'),
                items: PainLevel.values
                    .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
                    .toList(),
                onChanged: (p) => setState(() => _rightPain = p),
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
                    onPressed: (_leftEye || _rightEye)
                        ? () {
                            widget.onSave(FlareUp(
                              id: widget.existing?.id ??
                                  DateTime.now().millisecondsSinceEpoch.toString(),
                              date: _date,
                              leftEye: _leftEye,
                              rightEye: _rightEye,
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
