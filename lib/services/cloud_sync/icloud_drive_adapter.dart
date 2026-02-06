import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../models/appointment_note.dart';
import '../../models/flare_up.dart';
import '../../models/medicine.dart';
import '../../models/medicine_dose.dart';
import 'cloud_sync_adapter.dart';

/// iCloud Drive adapter for iOS
class ICloudDriveAdapter implements ICloudSyncAdapter {
  Directory? _iCloudDir;
  static const String _medicinesFile = 'medicines.json';
  static const String _dosesFile = 'doses.json';
  static const String _flareUpsFile = 'flareUps.json';
  static const String _appointmentsFile = 'appointments.json';

  @override
  Future<void> init() async {
    if (!Platform.isIOS) {
      throw UnsupportedError('iCloud Drive is only available on iOS');
    }

    try {
      // Try to get iCloud container directory
      // Note: This requires iCloud Drive capability to be enabled in Xcode
      final dir = await getApplicationDocumentsDirectory();
      // For iCloud, we'd typically use a container URL, but path_provider
      // doesn't directly support it. We'll use a subdirectory approach.
      // In production, you might want to use a package like 'icloud_documents'
      // or implement native code to get the iCloud container URL.
      _iCloudDir = Directory('${dir.path}/iCloud');
      if (!await _iCloudDir!.exists()) {
        await _iCloudDir!.create(recursive: true);
      }
    } catch (e) {
      // If iCloud is not available, we'll handle it gracefully
      _iCloudDir = null;
    }
  }

  @override
  Future<bool> isAvailable() async {
    if (_iCloudDir == null) return false;
    // Check if iCloud directory is accessible
    try {
      return await _iCloudDir!.exists();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isSignedIn() async {
    // On iOS, iCloud is automatically available if signed into iCloud
    return await isAvailable();
  }

  @override
  Future<void> signIn() async {
    // On iOS, iCloud sign-in is handled by the system
    // User needs to sign in via Settings
    if (!await isAvailable()) {
      throw Exception('iCloud Drive is not available. Please sign in to iCloud in Settings.');
    }
  }

  @override
  Future<void> signOut() async {
    // On iOS, sign-out is handled by the system
    // We just clear our reference
    _iCloudDir = null;
  }

  Future<File> _getFile(String filename) async {
    if (_iCloudDir == null) {
      throw Exception('iCloud Drive not initialized');
    }
    return File('${_iCloudDir!.path}/$filename');
  }

  Future<void> _writeJsonFile(String filename, List<dynamic> data) async {
    final file = await _getFile(filename);
    await file.writeAsString(jsonEncode(data));
  }

  Future<List<dynamic>> _readJsonFile(String filename) async {
    final file = await _getFile(filename);
    if (!await file.exists()) {
      return [];
    }
    final content = await file.readAsString();
    if (content.isEmpty) return [];
    return jsonDecode(content) as List;
  }

  @override
  Future<void> syncMedicines(List<Medicine> medicines) async {
    await _writeJsonFile(
      _medicinesFile,
      medicines.map((m) => m.toJson()).toList(),
    );
  }

  @override
  Future<List<Medicine>> getMedicines() async {
    final data = await _readJsonFile(_medicinesFile);
    return data
        .map((e) => Medicine.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> syncDoses(List<MedicineDose> doses) async {
    await _writeJsonFile(
      _dosesFile,
      doses.map((d) => d.toJson()).toList(),
    );
  }

  @override
  Future<List<MedicineDose>> getDoses() async {
    final data = await _readJsonFile(_dosesFile);
    return data
        .map((e) => MedicineDose.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> syncFlareUps(List<FlareUp> flareUps) async {
    await _writeJsonFile(
      _flareUpsFile,
      flareUps.map((f) => f.toJson()).toList(),
    );
  }

  @override
  Future<List<FlareUp>> getFlareUps() async {
    final data = await _readJsonFile(_flareUpsFile);
    return data
        .map((e) => FlareUp.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> syncAppointments(List<AppointmentNote> appointments) async {
    await _writeJsonFile(
      _appointmentsFile,
      appointments.map((a) => a.toJson()).toList(),
    );
  }

  @override
  Future<List<AppointmentNote>> getAppointments() async {
    final data = await _readJsonFile(_appointmentsFile);
    return data
        .map((e) => AppointmentNote.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
