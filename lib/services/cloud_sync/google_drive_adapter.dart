import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import '../../models/appointment_note.dart';
import '../../models/flare_up.dart';
import '../../models/medicine.dart';
import '../../models/medicine_dose.dart';
import 'cloud_sync_adapter.dart';

/// Google Drive adapter for Android
class GoogleDriveAdapter implements ICloudSyncAdapter {
  GoogleSignIn? _googleSignIn;
  drive.DriveApi? _driveApi;
  static const String _medicinesFile = 'medicines.json';
  static const String _dosesFile = 'doses.json';
  static const String _flareUpsFile = 'flareUps.json';
  static const String _appointmentsFile = 'appointments.json';

  GoogleDriveAdapter() {
    if (Platform.isAndroid) {
      _googleSignIn = GoogleSignIn(
        scopes: [
          'https://www.googleapis.com/auth/drive.appdata',
        ],
      );
    }
  }

  @override
  Future<void> init() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('Google Drive adapter is only available on Android');
    }
    // Initialization happens when user signs in
  }

  Future<void> _ensureSignedIn() async {
    if (_googleSignIn == null) {
      throw UnsupportedError('Google Sign-In not available');
    }

    final account = await _googleSignIn!.signInSilently();
    if (account == null) {
      throw Exception('Not signed in to Google Drive');
    }

    if (_driveApi == null) {
      final authHeaders = await account.authHeaders;
      final client = GoogleAuthClient(authHeaders);
      _driveApi = drive.DriveApi(client);
    }
  }

  @override
  Future<bool> isAvailable() async {
    return Platform.isAndroid;
  }

  @override
  Future<bool> isSignedIn() async {
    if (_googleSignIn == null) return false;
    try {
      final account = await _googleSignIn!.signInSilently();
      return account != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> signIn() async {
    if (_googleSignIn == null) {
      throw UnsupportedError('Google Sign-In not available');
    }
    final account = await _googleSignIn!.signIn();
    if (account == null) {
      throw Exception('Google sign-in was cancelled');
    }
    final authHeaders = await account.authHeaders;
    final client = GoogleAuthClient(authHeaders);
    _driveApi = drive.DriveApi(client);
  }

  @override
  Future<void> signOut() async {
    await _googleSignIn?.signOut();
    _driveApi = null;
  }

  Future<String?> _findFileId(String filename) async {
    await _ensureSignedIn();
    if (_driveApi == null) return null;

    try {
      final files = await _driveApi!.files.list(
        q: "name='$filename' and 'appDataFolder' in parents",
        spaces: 'appDataFolder',
      );
      if (files.files != null && files.files!.isNotEmpty) {
        return files.files!.first.id;
      }
    } catch (_) {
      // File doesn't exist yet
    }
    return null;
  }

  Future<void> _writeFile(String filename, String content) async {
    await _ensureSignedIn();
    if (_driveApi == null) throw Exception('Drive API not initialized');

    final fileId = await _findFileId(filename);
    final file = drive.File()..name = filename;
    final bytes = utf8.encode(content);
    final media = drive.Media(
      Stream.value(Uint8List.fromList(bytes)),
      bytes.length,
      contentType: 'application/json',
    );

    if (fileId != null) {
      // Update existing file
      await _driveApi!.files.update(
        file,
        fileId,
        uploadMedia: media,
      );
    } else {
      // Create new file
      file.parents = ['appDataFolder'];
      await _driveApi!.files.create(
        file,
        uploadMedia: media,
      );
    }
  }

  Future<String?> _readFile(String filename) async {
    await _ensureSignedIn();
    if (_driveApi == null) return null;

    final fileId = await _findFileId(filename);
    if (fileId == null) return null;

    try {
      final response = await _driveApi!.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      );
      
      if (response is! drive.Media) return null;
      
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
      }
      return utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> syncMedicines(List<Medicine> medicines) async {
    final json = jsonEncode(medicines.map((m) => m.toJson()).toList());
    await _writeFile(_medicinesFile, json);
  }

  @override
  Future<List<Medicine>> getMedicines() async {
    final content = await _readFile(_medicinesFile);
    if (content == null || content.isEmpty) return [];
    final data = jsonDecode(content) as List;
    return data
        .map((e) => Medicine.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> syncDoses(List<MedicineDose> doses) async {
    final json = jsonEncode(doses.map((d) => d.toJson()).toList());
    await _writeFile(_dosesFile, json);
  }

  @override
  Future<List<MedicineDose>> getDoses() async {
    final content = await _readFile(_dosesFile);
    if (content == null || content.isEmpty) return [];
    final data = jsonDecode(content) as List;
    return data
        .map((e) => MedicineDose.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> syncFlareUps(List<FlareUp> flareUps) async {
    final json = jsonEncode(flareUps.map((f) => f.toJson()).toList());
    await _writeFile(_flareUpsFile, json);
  }

  @override
  Future<List<FlareUp>> getFlareUps() async {
    final content = await _readFile(_flareUpsFile);
    if (content == null || content.isEmpty) return [];
    final data = jsonDecode(content) as List;
    return data
        .map((e) => FlareUp.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> syncAppointments(List<AppointmentNote> appointments) async {
    final json = jsonEncode(appointments.map((a) => a.toJson()).toList());
    await _writeFile(_appointmentsFile, json);
  }

  @override
  Future<List<AppointmentNote>> getAppointments() async {
    final content = await _readFile(_appointmentsFile);
    if (content == null || content.isEmpty) return [];
    final data = jsonDecode(content) as List;
    return data
        .map((e) => AppointmentNote.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

/// HTTP client wrapper for Google API authentication
class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }

  @override
  void close() {
    _client.close();
  }
}
