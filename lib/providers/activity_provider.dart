import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/activity_item.dart';
import 'appointment_provider.dart';
import 'dose_provider.dart';
import 'flare_up_provider.dart';
import 'medicine_provider.dart';

/// Combined activity log: doses, flare-ups, appointments. Sorted by date descending.
final activityLogProvider = Provider<AsyncValue<List<ActivityItem>>>((ref) {
  final dosesAsync = ref.watch(dosesProvider);
  final flareUpsAsync = ref.watch(flareUpsProvider);
  final appointmentsAsync = ref.watch(appointmentsProvider);
  final medicinesAsync = ref.watch(medicinesProvider);

  if (dosesAsync.isLoading || flareUpsAsync.isLoading ||
      appointmentsAsync.isLoading || medicinesAsync.isLoading) {
    return const AsyncValue.loading();
  }
  final doses = dosesAsync.valueOrNull ?? [];
  final flareUps = flareUpsAsync.valueOrNull ?? [];
  final appointments = appointmentsAsync.valueOrNull ?? [];
  final medicines = medicinesAsync.valueOrNull ?? [];

  if (dosesAsync.hasError) return AsyncValue.error(dosesAsync.error!, dosesAsync.stackTrace ?? StackTrace.current);
  if (flareUpsAsync.hasError) return AsyncValue.error(flareUpsAsync.error!, flareUpsAsync.stackTrace ?? StackTrace.current);
  if (appointmentsAsync.hasError) return AsyncValue.error(appointmentsAsync.error!, appointmentsAsync.stackTrace ?? StackTrace.current);
  if (medicinesAsync.hasError) return AsyncValue.error(medicinesAsync.error!, medicinesAsync.stackTrace ?? StackTrace.current);

  final medicineById = {for (final m in medicines) m.id: m};
  final items = <ActivityItem>[];

  for (final d in doses) {
    final name = medicineById[d.medicineId]?.name ?? 'Unknown';
    items.add(ActivityItem.fromDose(d, name));
  }
  for (final f in flareUps) {
    items.add(ActivityItem.fromFlareUp(f));
  }
  for (final a in appointments) {
    items.add(ActivityItem.fromAppointment(a));
  }

  items.sort((a, b) => b.date.compareTo(a.date));
  return AsyncValue.data(items);
});
