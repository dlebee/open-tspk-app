import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/appointment_note.dart';
import '../models/flare_up.dart';
import '../models/medicine.dart';
import '../models/medicine_dose.dart';

class ExportService {
  static String export({
    required List<Medicine> medicines,
    required List<MedicineDose> doses,
    required List<FlareUp> flareUps,
    required List<AppointmentNote> appointments,
  }) {
    final data = {
      'exportedAt': DateTime.now().toIso8601String(),
      'medicines': medicines.map((m) => m.toJson()).toList(),
      'doses': doses.map((d) => d.toJson()).toList(),
      'flareUps': flareUps.map((f) => f.toJson()).toList(),
      'appointments': appointments.map((a) => a.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  static Future<void> share(String jsonContent) async {
    final dir = await getTemporaryDirectory();
    final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final file = File('${dir.path}/thygeson_export_$dateStr.json');
    await file.writeAsString(jsonContent);
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Thygeson data export',
    );
  }
}

