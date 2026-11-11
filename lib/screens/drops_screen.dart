import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/medicine.dart';
import '../theme/dusk_theme.dart';
import '../ui/dusk_ui.dart';
import '../providers/medicine_provider.dart';
import 'drop_edit_screen.dart';
import 'settings_screen.dart';

class DropsScreen extends ConsumerWidget {
  const DropsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final medicines = ref.watch(medicinesProvider).value ?? [];
    void open(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

    return DuskPage(
      title: 'Your drops',
      subtitle: 'What you take, and when.',
      children: [
        for (final m in medicines) ...[
          _DropCard(medicine: m, onTap: () => open(DropEditScreen(medicine: m))),
          const SizedBox(height: 12),
        ],
        Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Dusk.border, width: 1.5),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => open(const DropEditScreen()),
            child: const SizedBox(
              height: 64,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add, color: Dusk.amber),
                  SizedBox(width: 8),
                  Text('Add a drop', style: TextStyle(color: Dusk.amber, fontWeight: FontWeight.w600, fontSize: 15)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        DuskTile(
          onTap: () => open(const SettingsScreen()),
          child: const Row(
            children: [
              Expanded(child: Text('Reminders, backup and sync', style: TextStyle(fontSize: 15, color: Dusk.text))),
              Icon(Icons.chevron_right, color: Dusk.textMuted),
            ],
          ),
        ),
      ],
    );
  }
}

class _DropCard extends StatelessWidget {
  const _DropCard({required this.medicine, required this.onTap});

  final Medicine medicine;
  final VoidCallback onTap;

  static const _short = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String _days(List<int> days) {
    if (days.length == 7) return 'every day';
    final sorted = [...days]..sort();
    if (sorted.join() == '12345') return 'weekdays';
    return sorted.map((d) => _short[d - 1]).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return DuskTile(
      radius: 20,
      padding: const EdgeInsets.all(18),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: Dusk.amberSoft, borderRadius: BorderRadius.circular(14)),
                child: Icon(
                  medicine.schedules.every((s) => s.eye == Eye.other) ? Icons.medication_outlined : Icons.water_drop_outlined,
                  color: Dusk.amber,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(medicine.name,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Dusk.text)),
              ),
              const Icon(Icons.chevron_right, color: Dusk.textMuted),
            ],
          ),
          for (final s in medicine.schedules) ...[
            const SizedBox(height: 12),
            Text('${eyeLabel(s.eye)} · ${_days(s.daysOfWeek)}',
                style: const TextStyle(fontSize: 13, color: Dusk.textSecondary)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in [...s.times]..sort())
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Dusk.surfaceHigh, borderRadius: BorderRadius.circular(10)),
                    child: Text(t, style: const TextStyle(fontSize: 13, color: Dusk.textSecondary)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
