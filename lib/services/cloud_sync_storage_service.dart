import '../models/appointment_note.dart';
import '../models/flare_up.dart';
import '../models/medicine.dart';
import '../models/medicine_dose.dart';
import 'cloud_sync/cloud_sync_adapter.dart';
import 'cloud_sync/conflict_resolver.dart';
import 'storage_service.dart';

/// Storage service that wraps local storage with cloud sync
class CloudSyncStorageService implements IStorageService {
  final LocalStorageService _localStorage;
  final ICloudSyncAdapter _cloudAdapter;
  bool _initialized = false;

  CloudSyncStorageService(
    this._localStorage,
    this._cloudAdapter,
  );

  /// Expose local storage for switching back to local-only mode
  LocalStorageService get localStorage => _localStorage;

  @override
  Future<void> init() async {
    if (_initialized) return;
    
    await _localStorage.init();
    await _cloudAdapter.init();
    _initialized = true;
    
    // Perform initial sync in background
    _syncInBackground();
  }

  /// Sync data in background without blocking
  Future<void> _syncInBackground() async {
    try {
      // Load from cloud and merge with local
      final cloudMedicines = await _cloudAdapter.getMedicines();
      final localMedicines = _localStorage.getMedicines();
      final mergedMedicines = ConflictResolver.mergeMedicines(
        localMedicines,
        cloudMedicines,
      );
      if (mergedMedicines.length != localMedicines.length ||
          !_listsEqual(mergedMedicines, localMedicines)) {
        await _localStorage.saveMedicines(mergedMedicines);
      }

      final cloudDoses = await _cloudAdapter.getDoses();
      final localDoses = _localStorage.getDoses();
      final mergedDoses = ConflictResolver.mergeDoses(localDoses, cloudDoses);
      if (mergedDoses.length != localDoses.length ||
          !_listsEqual(mergedDoses, localDoses)) {
        await _localStorage.saveDoses(mergedDoses);
      }

      final cloudFlareUps = await _cloudAdapter.getFlareUps();
      final localFlareUps = _localStorage.getFlareUps();
      final mergedFlareUps = ConflictResolver.mergeFlareUps(
        localFlareUps,
        cloudFlareUps,
      );
      if (mergedFlareUps.length != localFlareUps.length ||
          !_listsEqual(mergedFlareUps, localFlareUps)) {
        await _localStorage.saveFlareUps(mergedFlareUps);
      }

      final cloudAppointments = await _cloudAdapter.getAppointments();
      final localAppointments = _localStorage.getAppointments();
      final mergedAppointments = ConflictResolver.mergeAppointments(
        localAppointments,
        cloudAppointments,
      );
      if (mergedAppointments.length != localAppointments.length ||
          !_listsEqual(mergedAppointments, localAppointments)) {
        await _localStorage.saveAppointments(mergedAppointments);
      }
    } catch (e) {
      // Silently fail - app continues to work with local data
      print('Background sync failed: $e');
    }
  }

  bool _listsEqual<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Sync to cloud in background
  Future<void> _syncToCloud() async {
    try {
      await _cloudAdapter.syncMedicines(_localStorage.getMedicines());
      await _cloudAdapter.syncDoses(_localStorage.getDoses());
      await _cloudAdapter.syncFlareUps(_localStorage.getFlareUps());
      await _cloudAdapter.syncAppointments(_localStorage.getAppointments());
    } catch (e) {
      // Silently fail - local data is already saved
      print('Cloud sync failed: $e');
    }
  }

  @override
  List<Medicine> getMedicines() {
    return _localStorage.getMedicines();
  }

  @override
  Future<void> saveMedicines(List<Medicine> medicines) async {
    // Save locally first (offline-first)
    await _localStorage.saveMedicines(medicines);
    // Sync to cloud in background
    Future.microtask(() => _cloudAdapter.syncMedicines(medicines).catchError((_) {}));
  }

  @override
  List<MedicineDose> getDoses() {
    return _localStorage.getDoses();
  }

  @override
  Future<void> saveDoses(List<MedicineDose> doses) async {
    await _localStorage.saveDoses(doses);
    Future.microtask(() => _cloudAdapter.syncDoses(doses).catchError((_) {}));
  }

  @override
  List<FlareUp> getFlareUps() {
    return _localStorage.getFlareUps();
  }

  @override
  Future<void> saveFlareUps(List<FlareUp> flareUps) async {
    await _localStorage.saveFlareUps(flareUps);
    Future.microtask(() => _cloudAdapter.syncFlareUps(flareUps).catchError((_) {}));
  }

  @override
  List<AppointmentNote> getAppointments() {
    return _localStorage.getAppointments();
  }

  @override
  Future<void> saveAppointments(List<AppointmentNote> appointments) async {
    await _localStorage.saveAppointments(appointments);
    Future.microtask(() => _cloudAdapter.syncAppointments(appointments).catchError((_) {}));
  }

  @override
  bool getDeveloperMode() {
    return _localStorage.getDeveloperMode();
  }

  @override
  Future<void> setDeveloperMode(bool enabled) async {
    await _localStorage.setDeveloperMode(enabled);
  }

  @override
  bool getCloudSyncEnabled() {
    return _localStorage.getCloudSyncEnabled();
  }

  @override
  Future<void> setCloudSyncEnabled(bool enabled) async {
    await _localStorage.setCloudSyncEnabled(enabled);
  }

  @override
  Future<void> wipeAllData() async {
    await _localStorage.wipeAllData();
    // Optionally wipe cloud data too
    try {
      await _cloudAdapter.syncMedicines([]);
      await _cloudAdapter.syncDoses([]);
      await _cloudAdapter.syncFlareUps([]);
      await _cloudAdapter.syncAppointments([]);
    } catch (_) {
      // Ignore cloud wipe errors
    }
  }

  /// Get the cloud adapter (for sign-in/sign-out operations)
  ICloudSyncAdapter get cloudAdapter => _cloudAdapter;
}
