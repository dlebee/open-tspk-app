import '../../models/appointment_note.dart';
import '../../models/flare_up.dart';
import '../../models/medicine.dart';
import '../../models/medicine_dose.dart';

/// Interface for platform-specific cloud sync adapters
abstract class ICloudSyncAdapter {
  /// Initialize the adapter
  Future<void> init();

  /// Check if cloud account is available
  Future<bool> isAvailable();

  /// Check if user is signed in (mainly for Android Google Drive)
  Future<bool> isSignedIn();

  /// Sign in to cloud service (mainly for Android Google Drive)
  Future<void> signIn();

  /// Sign out from cloud service
  Future<void> signOut();

  /// Sync medicines to cloud
  Future<void> syncMedicines(List<Medicine> medicines);

  /// Get medicines from cloud
  Future<List<Medicine>> getMedicines();

  /// Sync doses to cloud
  Future<void> syncDoses(List<MedicineDose> doses);

  /// Get doses from cloud
  Future<List<MedicineDose>> getDoses();

  /// Sync flare-ups to cloud
  Future<void> syncFlareUps(List<FlareUp> flareUps);

  /// Get flare-ups from cloud
  Future<List<FlareUp>> getFlareUps();

  /// Sync appointments to cloud
  Future<void> syncAppointments(List<AppointmentNote> appointments);

  /// Get appointments from cloud
  Future<List<AppointmentNote>> getAppointments();
}
