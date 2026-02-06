import 'dart:io';

import 'cloud_sync_adapter.dart';
import 'google_drive_adapter.dart';
import 'icloud_drive_adapter.dart';

/// Factory for creating platform-specific cloud sync adapters
class CloudSyncService {
  /// Create the appropriate cloud sync adapter for the current platform
  static ICloudSyncAdapter createAdapter() {
    if (Platform.isIOS) {
      return ICloudDriveAdapter();
    } else if (Platform.isAndroid) {
      return GoogleDriveAdapter();
    } else {
      throw UnsupportedError('Cloud sync is only supported on iOS and Android');
    }
  }
}
