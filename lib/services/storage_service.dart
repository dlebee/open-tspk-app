import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../models/appointment_note.dart';
import '../models/flare_up.dart';
import '../models/medicine.dart';
import '../models/medicine_dose.dart';

class StorageService {
  static const _medicinesBox = 'medicines';
  static const _dosesBox = 'doses';
  static const _flareUpsBox = 'flareUps';
  static const _appointmentsBox = 'appointments';

  Box<String>? _medicines;
  Box<String>? _doses;
  Box<String>? _flareUps;
  Box<String>? _appointments;

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    await Hive.initFlutter(dir.path);

    _medicines = await Hive.openBox<String>(_medicinesBox);
    _doses = await Hive.openBox<String>(_dosesBox);
    _flareUps = await Hive.openBox<String>(_flareUpsBox);
    _appointments = await Hive.openBox<String>(_appointmentsBox);
  }

  List<Medicine> getMedicines() {
    final raw = _medicines?.get('list');
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => Medicine.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveMedicines(List<Medicine> medicines) async {
    await _medicines?.put(
      'list',
      jsonEncode(medicines.map((m) => m.toJson()).toList()),
    );
  }

  List<MedicineDose> getDoses() {
    final raw = _doses?.get('list');
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => MedicineDose.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveDoses(List<MedicineDose> doses) async {
    await _doses?.put(
      'list',
      jsonEncode(doses.map((d) => d.toJson()).toList()),
    );
  }

  List<FlareUp> getFlareUps() {
    final raw = _flareUps?.get('list');
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => FlareUp.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveFlareUps(List<FlareUp> flareUps) async {
    await _flareUps?.put(
      'list',
      jsonEncode(flareUps.map((f) => f.toJson()).toList()),
    );
  }

  List<AppointmentNote> getAppointments() {
    final raw = _appointments?.get('list');
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => AppointmentNote.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveAppointments(List<AppointmentNote> appointments) async {
    await _appointments?.put(
      'list',
      jsonEncode(appointments.map((a) => a.toJson()).toList()),
    );
  }
}
