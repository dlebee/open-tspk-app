import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/appointment_note.dart';
import '../models/flare_up.dart';
import '../models/medicine.dart';
import '../models/medicine_dose.dart';

/// Parsed result of an export file for import.
class ImportData {
  final List<Medicine> medicines;
  final List<MedicineDose> doses;
  final List<FlareUp> flareUps;
  final List<AppointmentNote> appointments;
  final DateTime? exportedAt;

  ImportData({
    required this.medicines,
    required this.doses,
    required this.flareUps,
    required this.appointments,
    this.exportedAt,
  });
}

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

  /// Shares exported JSON. [sharePositionOrigin] is required on iPad for the
  /// share sheet popover anchor; pass the tapped widget's rect from context.
  static Future<void> share(
    String jsonContent, {
    Rect? sharePositionOrigin,
  }) async {
    final dir = await getTemporaryDirectory();
    final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final file = File('${dir.path}/thygeson_export_$dateStr.json');
    await file.writeAsString(jsonContent);
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Thygeson data export',
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  /// Parses a previously exported JSON string. Throws on invalid format.
  static ImportData parseImport(String jsonContent) {
    final data = jsonDecode(jsonContent) as Map<String, dynamic>;
    if (data['medicines'] == null && data['doses'] == null &&
        data['flareUps'] == null && data['appointments'] == null) {
      throw FormatException(
        'Invalid export file: expected medicines, doses, flareUps, appointments',
      );
    }
    final medicines = (data['medicines'] as List?)
            ?.map((e) => Medicine.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final doses = (data['doses'] as List?)
            ?.map((e) => MedicineDose.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final flareUps = (data['flareUps'] as List?)
            ?.map((e) => FlareUp.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final appointments = (data['appointments'] as List?)
            ?.map((e) => AppointmentNote.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    DateTime? exportedAt;
    if (data['exportedAt'] != null) {
      exportedAt = DateTime.tryParse(data['exportedAt'] as String);
    }
    return ImportData(
      medicines: medicines,
      doses: doses,
      flareUps: flareUps,
      appointments: appointments,
      exportedAt: exportedAt,
    );
  }

  /// Prompts user to pick an exported JSON file. Returns parsed data or null
  /// if cancelled or failed.
  static Future<ImportData?> pickAndParseImport() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.single;
    String content;
    if (file.bytes != null) {
      content = utf8.decode(file.bytes!);
    } else if (file.path != null) {
      content = await File(file.path!).readAsString();
    } else {
      return null;
    }
    return parseImport(content);
  }
}

