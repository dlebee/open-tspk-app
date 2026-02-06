import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../models/appointment_note.dart';
import '../models/flare_up.dart';
import '../models/medicine.dart';
import '../models/medicine_dose.dart';

/// Abstract interface for storage operations
abstract class IStorageService {
  Future<void> init();
  List<Medicine> getMedicines();
  Future<void> saveMedicines(List<Medicine> medicines);
  List<MedicineDose> getDoses();
  Future<void> saveDoses(List<MedicineDose> doses);
  List<FlareUp> getFlareUps();
  Future<void> saveFlareUps(List<FlareUp> flareUps);
  List<AppointmentNote> getAppointments();
  Future<void> saveAppointments(List<AppointmentNote> appointments);
  bool getDeveloperMode();
  Future<void> setDeveloperMode(bool enabled);
  bool getCloudSyncEnabled();
  Future<void> setCloudSyncEnabled(bool enabled);
  Future<void> wipeAllData();
}

/// Local storage implementation using Hive
class LocalStorageService implements IStorageService {
  static const _medicinesBox = 'medicines';
  static const _dosesBox = 'doses';
  static const _flareUpsBox = 'flareUps';
  static const _appointmentsBox = 'appointments';
  static const _preferencesBox = 'preferences';

  Box<String>? _medicines;
  Box<String>? _doses;
  Box<String>? _flareUps;
  Box<String>? _appointments;
  Box<String>? _preferences;

  @override
  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    await Hive.initFlutter(dir.path);

    _medicines = await Hive.openBox<String>(_medicinesBox);
    _doses = await Hive.openBox<String>(_dosesBox);
    _flareUps = await Hive.openBox<String>(_flareUpsBox);
    _appointments = await Hive.openBox<String>(_appointmentsBox);
    _preferences = await Hive.openBox<String>(_preferencesBox);
  }

  @override
  List<Medicine> getMedicines() {
    final raw = _medicines?.get('list');
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => Medicine.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> saveMedicines(List<Medicine> medicines) async {
    await _medicines?.put(
      'list',
      jsonEncode(medicines.map((m) => m.toJson()).toList()),
    );
  }

  @override
  List<MedicineDose> getDoses() {
    final raw = _doses?.get('list');
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => MedicineDose.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> saveDoses(List<MedicineDose> doses) async {
    await _doses?.put(
      'list',
      jsonEncode(doses.map((d) => d.toJson()).toList()),
    );
  }

  @override
  List<FlareUp> getFlareUps() {
    final raw = _flareUps?.get('list');
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => FlareUp.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> saveFlareUps(List<FlareUp> flareUps) async {
    await _flareUps?.put(
      'list',
      jsonEncode(flareUps.map((f) => f.toJson()).toList()),
    );
  }

  @override
  List<AppointmentNote> getAppointments() {
    final raw = _appointments?.get('list');
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => AppointmentNote.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> saveAppointments(List<AppointmentNote> appointments) async {
    await _appointments?.put(
      'list',
      jsonEncode(appointments.map((a) => a.toJson()).toList()),
    );
  }

  @override
  bool getDeveloperMode() {
    final raw = _preferences?.get('developerMode');
    if (raw == null) return false;
    return raw == 'true';
  }

  @override
  Future<void> setDeveloperMode(bool enabled) async {
    await _preferences?.put('developerMode', enabled ? 'true' : 'false');
  }

  @override
  bool getCloudSyncEnabled() {
    final raw = _preferences?.get('cloudSyncEnabled');
    if (raw == null) return false;
    return raw == 'true';
  }

  @override
  Future<void> setCloudSyncEnabled(bool enabled) async {
    await _preferences?.put('cloudSyncEnabled', enabled ? 'true' : 'false');
  }

  /// Wipes all data from all boxes. This is irreversible.
  /// Preserves developer mode setting.
  @override
  Future<void> wipeAllData() async {
    // Preserve developer mode setting before clearing preferences
    final developerModeEnabled = getDeveloperMode();
    
    await _medicines?.clear();
    await _doses?.clear();
    await _flareUps?.clear();
    await _appointments?.clear();
    await _preferences?.clear();
    
    // Restore developer mode setting
    if (developerModeEnabled) {
      await setDeveloperMode(true);
    }
  }
}
