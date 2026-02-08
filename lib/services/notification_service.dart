import 'dart:convert';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/medicine.dart';
import '../models/medicine_dose.dart';
import '../models/notification_reminder_preference.dart';
import 'storage_service.dart';

class NotificationService {
  // #region agent log
  static void _debugLog(String location, String message, Map<String, dynamic> data) {
    try {
      final logFile = File('/Users/gluwadl/Dev/open-tspk-app/.cursor/debug.log');
      final logEntry = jsonEncode({
        'id': 'log_${DateTime.now().millisecondsSinceEpoch}',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'location': location,
        'message': message,
        'data': data,
      });
      logFile.writeAsStringSync('$logEntry\n', mode: FileMode.append);
    } catch (e) {
      // Ignore logging errors
    }
  }
  // #endregion
  static final _plugin = FlutterLocalNotificationsPlugin();
  static IStorageService? _storage;
  static void Function(String medicineId, String eye, String scheduledDate, String scheduledTime)? _onOverrideTimeRequested;
  static void Function()? _onDoseAdded;
  static void Function(String medicineId, String scheduleId, String eye, String scheduledDate, String scheduledTime)? _onNotificationTapped;
  
  // Track notification ID assignments for cancellation
  // Key: 'medicineId|scheduleId|dayOfWeek|timeIndex|offset'
  static final Map<String, int> _notificationIdMap = {};
  
  // Lock for atomic notification ID generation
  static bool _idGenerationInProgress = false;

  static void setStorage(IStorageService storage) {
    _storage = storage;
  }

  static void setOnOverrideTimeRequested(void Function(String, String, String, String) fn) {
    _onOverrideTimeRequested = fn;
  }

  static void setOnDoseAdded(void Function() fn) {
    _onDoseAdded = fn;
  }

  static void setOnNotificationTapped(void Function(String medicineId, String scheduleId, String eye, String scheduledDate, String scheduledTime) fn) {
    _onNotificationTapped = fn;
  }

  static Future<void> init() async {
    print('[NotificationService] Initializing notification service...');
    try {
      tz_data.initializeTimeZones();
      print('[NotificationService] Timezone data initialized');
      
      // Get the device's actual timezone using flutter_timezone
      final systemNow = DateTime.now();
      print('[NotificationService] System timezone offset: ${systemNow.timeZoneOffset}');
      
      try {
        final timezoneInfo = await FlutterTimezone.getLocalTimezone();
        final timezoneName = timezoneInfo.identifier;
        print('[NotificationService] Device timezone (from flutter_timezone): $timezoneName');
        
        final location = tz.getLocation(timezoneName);
        tz.setLocalLocation(location);
        print('[NotificationService] Set local timezone to: ${tz.local.name}');
      } catch (e) {
        print('[NotificationService] WARNING: Could not get device timezone: $e');
        // Fallback: try to match by offset (less reliable but better than UTC)
        final offsetHours = systemNow.timeZoneOffset.inHours;
        final offsetMinutes = systemNow.timeZoneOffset.inMinutes % 60;
        print('[NotificationService] Falling back to offset-based detection: ${offsetHours}h ${offsetMinutes}m');
        
        String? fallbackTimezone;
        if (offsetHours == -5 && offsetMinutes == 0) fallbackTimezone = 'America/New_York';
        else if (offsetHours == -6 && offsetMinutes == 0) fallbackTimezone = 'America/Chicago';
        else if (offsetHours == -7 && offsetMinutes == 0) fallbackTimezone = 'America/Denver';
        else if (offsetHours == -8 && offsetMinutes == 0) fallbackTimezone = 'America/Los_Angeles';
        else if (offsetHours == 0 && offsetMinutes == 0) fallbackTimezone = 'Europe/London';
        else if (offsetHours == 1 && offsetMinutes == 0) fallbackTimezone = 'Europe/Paris';
        else if (offsetHours == 9 && offsetMinutes == 0) fallbackTimezone = 'Asia/Tokyo';
        
        if (fallbackTimezone != null) {
          try {
            tz.setLocalLocation(tz.getLocation(fallbackTimezone));
            print('[NotificationService] Set fallback timezone to: ${tz.local.name}');
          } catch (e2) {
            print('[NotificationService] WARNING: Fallback timezone also failed: $e2. Using UTC.');
          }
        } else {
          print('[NotificationService] WARNING: Unknown timezone offset, using UTC. Notifications may fire at wrong times.');
        }
      }
      
      print('[NotificationService] System local time: $systemNow');
      print('[NotificationService] System timezone offset: ${systemNow.timeZoneOffset}');
      print('[NotificationService] System date: ${systemNow.year}-${systemNow.month.toString().padLeft(2, '0')}-${systemNow.day.toString().padLeft(2, '0')}');
      
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      // Configure iOS to show notifications even when app is in foreground
      // Register notification categories with action buttons for iOS
      final ios = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
        defaultPresentAlert: true, // Show alert when app is in foreground
        defaultPresentSound: true, // Play sound when app is in foreground
        defaultPresentBadge: true, // Update badge when app is in foreground
        defaultPresentBanner: true, // Show banner when app is in foreground (iOS 15+)
        defaultPresentList: true, // Show in notification center when app is in foreground
        notificationCategories: [
          DarwinNotificationCategory(
            'thygeson_meds',
            actions: <DarwinNotificationAction>[
              DarwinNotificationAction.plain('skip', 'Skip'),
              DarwinNotificationAction.plain('taken_on_time', 'Taken on time'),
              DarwinNotificationAction.plain('taken_now', 'Taken now'),
              DarwinNotificationAction.plain('taken_at_override', 'Taken at...', 
                options: <DarwinNotificationActionOption>{
                  DarwinNotificationActionOption.foreground,
                },
              ),
            ],
            options: <DarwinNotificationCategoryOption>{
              DarwinNotificationCategoryOption.hiddenPreviewShowTitle,
            },
          ),
        ],
      );
      final initialized = await _plugin.initialize(
        InitializationSettings(android: android, iOS: ios),
        onDidReceiveNotificationResponse: _onNotificationResponse,
      );
      print('[NotificationService] Plugin initialized: $initialized');
      
      // Create notification channel for Android
      if (Platform.isAndroid) {
        print('[NotificationService] Setting up Android notification channel...');
        const androidChannel = AndroidNotificationChannel(
          'thygeson_meds',
          'Medicine reminders',
          description: 'Reminders for scheduled medicine',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        );
        final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        if (androidPlugin != null) {
          await androidPlugin.createNotificationChannel(androidChannel);
          print('[NotificationService] Android notification channel created');
          
          final permissionGranted = await androidPlugin.requestNotificationsPermission();
          print('[NotificationService] Android notification permission granted: $permissionGranted');
          
          // Check exact alarm permission (required for exactAllowWhileIdle on Android 12+)
          try {
            // Note: The plugin may handle this internally, but we log it for debugging
            final areNotificationsEnabled = await androidPlugin.areNotificationsEnabled();
            print('[NotificationService] Android notifications enabled: $areNotificationsEnabled');
            print('[NotificationService] Using AndroidScheduleMode.exactAllowWhileIdle - requires SCHEDULE_EXACT_ALARM permission');
            print('[NotificationService] Note: On Android 12+, user must grant exact alarm permission in system settings');
          } catch (e) {
            print('[NotificationService] Could not check exact alarm permission status: $e');
          }
        } else {
          print('[NotificationService] WARNING: Android plugin not available');
        }
      }
      
      // Request notification permissions on iOS
      if (Platform.isIOS) {
        print('[NotificationService] Requesting iOS notification permissions...');
        final iosPlugin = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
        if (iosPlugin != null) {
          final permissions = await iosPlugin.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
          print('[NotificationService] iOS notification permissions: $permissions');
        } else {
          print('[NotificationService] WARNING: iOS plugin not available');
        }
      }
      
      print('[NotificationService] Initialization complete');
      
      // Log permission status after initialization
      await logPermissionStatus();
    } catch (e, stackTrace) {
      print('[NotificationService] ERROR during initialization: $e');
      print('[NotificationService] Stack trace: $stackTrace');
      rethrow;
    }
  }

  static Future<void> _onNotificationResponse(NotificationResponse response) async {
    final payload = response.payload;
    if (payload == null || _storage == null) return;
    try {
      final map = jsonDecode(payload) as Map<String, dynamic>;
      final medicineId = map['medicineId'] as String?;
      final scheduleId = map['scheduleId'] as String?;
      final eyeStr = map['eye'] as String?;
      final scheduledDate = map['scheduledDate'] as String?;
      final scheduledTime = map['scheduledTime'] as String?;
      if (medicineId == null || scheduleId == null || eyeStr == null || scheduledDate == null || scheduledTime == null) return;

      final eye = Eye.values.firstWhere((e) => e.name == eyeStr, orElse: () => Eye.both);
      final scheduledDt = DateTime.parse(scheduledDate);

      // Handle notification tap (no action button pressed)
      if (response.actionId == null || response.actionId == '') {
        _onNotificationTapped?.call(medicineId, scheduleId, eyeStr, scheduledDate, scheduledTime);
        return;
      }

      switch (response.actionId) {
        case 'skip':
          await _addDose(medicineId, eye, scheduledDt, scheduledTime, DoseStatus.skipped, null);
          break;
        case 'taken_on_time':
          final takenAt = DateTime(scheduledDt.year, scheduledDt.month, scheduledDt.day,
              int.parse(scheduledTime.split(':')[0]), int.parse(scheduledTime.split(':')[1]));
          await _addDose(medicineId, eye, scheduledDt, scheduledTime, DoseStatus.taken, takenAt);
          break;
        case 'taken_now':
          await _addDose(medicineId, eye, scheduledDt, scheduledTime, DoseStatus.taken, DateTime.now());
          break;
        case 'taken_at_override':
          _onOverrideTimeRequested?.call(medicineId, eyeStr, scheduledDate, scheduledTime);
          break;
      }
    } catch (_) {}
  }

  static Future<void> _addDose(String medicineId, Eye eye, DateTime scheduledDate, String scheduledTime, DoseStatus status, DateTime? takenAt) async {
    final storage = _storage;
    if (storage == null) return;
    final doses = storage.getDoses();
    // Look up medicine name for denormalization
    final medicines = storage.getMedicines();
    final medicine = medicines.firstWhere((m) => m.id == medicineId, orElse: () => Medicine(name: 'Unknown', schedules: [], createdAt: DateTime.now()));
    
    // Cancel remaining notifications for this schedule
    await _cancelForSchedule(medicineId, scheduledDate, scheduledTime, eye);
    
    // For skipped doses, use scheduled date/time as recordedAt
    // For taken doses, use DateTime.now() as recordedAt
    DateTime recordedAt;
    if (status == DoseStatus.skipped) {
      final parts = scheduledTime.split(':');
      recordedAt = DateTime(
        scheduledDate.year,
        scheduledDate.month,
        scheduledDate.day,
        int.parse(parts[0]),
        parts.length > 1 ? int.parse(parts[1]) : 0,
      );
    } else {
      recordedAt = DateTime.now();
    }
    
    final dose = MedicineDose(
      medicineId: medicineId,
      medicineName: medicine.name,
      eye: eye,
      status: status,
      recordedAt: recordedAt,
      scheduledDate: scheduledDate,
      scheduledTime: scheduledTime,
      takenAt: takenAt,
    );
    storage.saveDoses([...doses, dose]);
    _onDoseAdded?.call();
  }
  
  /// Cancel all notifications for a specific schedule (all 3: 15min before, 10min before, at time)
  static Future<void> _cancelForSchedule(String medicineId, DateTime scheduledDate, String scheduledTime, Eye eye) async {
    print('[NotificationService] Cancelling notifications for schedule: medicineId=$medicineId, date=$scheduledDate, time=$scheduledTime, eye=$eye');
    
    final storage = _storage;
    if (storage == null) {
      print('[NotificationService] ✗ Storage not available, cannot cancel schedule');
      return;
    }
    
    final medicines = storage.getMedicines();
    final medicineIndex = medicines.indexWhere((m) => m.id == medicineId);
    if (medicineIndex == -1) {
      print('[NotificationService] ✗ Medicine not found for ID: $medicineId');
      return;
    }
    final medicine = medicines[medicineIndex];
    
    final parts = scheduledTime.split(':');
    final hour = int.parse(parts[0]);
    final minute = parts.length > 1 ? int.parse(parts[1]) : 0;
    final scheduledWeekday = scheduledDate.weekday;
    
    print('[NotificationService] Looking for schedule matching: weekday=$scheduledWeekday, time=$scheduledTime, eye=$eye');
    print('[NotificationService] Medicine has ${medicine.schedules.length} schedule(s)');
    
    // Find the matching schedule
    bool found = false;
    for (final schedule in medicine.schedules) {
      print('[NotificationService] Checking schedule ${schedule.id}: eye=${schedule.eye.name}, days=${schedule.daysOfWeek}, times=${schedule.times}');
      
      if (schedule.eye != eye) {
        print('[NotificationService] Eye mismatch (expected $eye, got ${schedule.eye.name}), skipping');
        continue;
      }
      
      // Check if this schedule has the matching time and day
      if (schedule.daysOfWeek.contains(scheduledWeekday) && schedule.times.contains(scheduledTime)) {
        final timeIndex = schedule.times.indexOf(scheduledTime);
        
        print('[NotificationService] Found matching schedule ${schedule.id}, time index $timeIndex');
        print('[NotificationService] Cancelling 4 notifications (15min before, 10min before, 5min before, at time)');
        
        // Cancel all 4 notifications (0=at time, 1=5min before, 2=10min before, 3=15min before)
        int cancelledCount = 0;
        for (var offset = 0; offset < 4; offset++) {
          final key = '$medicineId|${schedule.id}|$scheduledWeekday|$timeIndex|$offset';
          final id = _notificationIdMap[key];
          if (id != null) {
            try {
              await _plugin.cancel(id);
              print('[NotificationService] ✓ Cancelled notification ID $id (offset=$offset)');
              cancelledCount++;
              // Remove from map after successful cancellation
              _notificationIdMap.remove(key);
            } catch (e) {
              print('[NotificationService] Could not cancel notification ID $id: $e (may not exist)');
            }
          } else {
            print('[NotificationService] No stored ID found for key: $key (may have been cancelled already)');
          }
        }
        print('[NotificationService] Cancelled $cancelledCount notification(s) for this schedule');
        found = true;
        break;
      } else {
        print('[NotificationService] Schedule ${schedule.id} does not match (days match: ${schedule.daysOfWeek.contains(scheduledWeekday)}, times match: ${schedule.times.contains(scheduledTime)})');
      }
    }
    
    if (!found) {
      print('[NotificationService] ✗ WARNING: No matching schedule found to cancel');
    }
  }

  /// Notification IDs must fit in 32-bit int (max: 2,147,483,647).
  /// Uses a simple incrementing counter that wraps back to 1 when it reaches the maximum.
  /// Each device maintains its own local counter (not synced across devices).
  /// This method is atomic to prevent duplicate IDs from concurrent calls.
  static Future<int> _getNextNotificationId() async {
    // Wait if another ID generation is in progress to prevent race conditions
    while (_idGenerationInProgress) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    
    _idGenerationInProgress = true;
    try {
      final storage = _storage;
      if (storage == null) {
        print('[NotificationService] WARNING: Storage not available, using default ID 1');
        return 1;
      }
      
      const maxId = 2147483647; // Maximum 32-bit signed integer
      int currentId = storage.getNextNotificationId();
      
      // Increment and wrap if needed
      int nextId = currentId + 1;
      if (nextId > maxId) {
        nextId = 1; // Wrap back to 1
        print('[NotificationService] Notification ID counter wrapped from $maxId back to 1');
      }
      
      // Save the next ID for future use
      await storage.setNextNotificationId(nextId);
      
      return currentId; // Return the ID we're using now (before increment)
    } finally {
      _idGenerationInProgress = false;
    }
  }
  
  /// Get or assign a notification ID for a specific notification.
  /// Uses incrementing counter and tracks assignments for cancellation.
  /// Always generates a new ID - the map is used for tracking, not for reusing IDs.
  static Future<int> _getId(String medicineId, String scheduleId, int dayOfWeek, int timeIndex, int notificationOffset) async {
    final key = '$medicineId|$scheduleId|$dayOfWeek|$timeIndex|$notificationOffset';
    
    // Always generate a new ID to ensure uniqueness
    // The map is used for tracking which ID is assigned to which notification for cancellation
    final id = await _getNextNotificationId();
    _notificationIdMap[key] = id;
    return id;
  }
  
  /// Clear notification ID mappings (useful when cancelling all or rescheduling)
  static void _clearNotificationIdMappings() {
    _notificationIdMap.clear();
  }

  /// Converts a local DateTime to TZDateTime for scheduling.
  /// Uses the system's local timezone (set in init()) to create the TZDateTime.
  static tz.TZDateTime _localToTZDateTime(DateTime localTime) {
    // #region agent log
    _debugLog('notification_service.dart:_localToTZDateTime:ENTRY', 'Converting local DateTime to TZDateTime', {
      'localTime': localTime.toString(),
      'localTimeIsUtc': localTime.isUtc,
      'timezoneOffset': localTime.timeZoneOffset.toString(),
      'tzLocalName': tz.local.name,
    });
    // #endregion
    
    print('[NotificationService] _localToTZDateTime: Converting $localTime (offset: ${localTime.timeZoneOffset})');
    print('[NotificationService] _localToTZDateTime: Current tz.local.name = ${tz.local.name}');
    
    // If tz.local is still UTC (timezone setting failed), we need to handle it differently
    // The plugin expects TZDateTime in the device's local timezone, not UTC
    if (tz.local.name == 'UTC') {
      print('[NotificationService] WARNING: tz.local is still UTC, timezone setting may have failed');
      print('[NotificationService] Creating TZDateTime.utc() and letting plugin handle conversion');
      // Convert local time to UTC first
      final utcTime = localTime.toUtc();
      final result = tz.TZDateTime.utc(
        utcTime.year,
        utcTime.month,
        utcTime.day,
        utcTime.hour,
        utcTime.minute,
        utcTime.second,
      );
      print('[NotificationService] Created UTC TZDateTime: $result');
      // #region agent log
      _debugLog('notification_service.dart:_localToTZDateTime:RESULT_UTC_FALLBACK', 'Created TZDateTime.utc (fallback)', {
        'localTime': localTime.toString(),
        'utcTime': utcTime.toString(),
        'resultTZDateTime': result.toString(),
        'resultYear': result.year,
        'resultMonth': result.month,
        'resultDay': result.day,
        'resultHour': result.hour,
        'resultMinute': result.minute,
        'resultIsUtc': result.isUtc,
        'resultLocation': result.location.name,
      });
      // #endregion
      return result;
    }
    
    // Use TZDateTime.from() with the local timezone (set in init())
    // This creates a TZDateTime in the system's local timezone, which the plugin can properly handle
    final result = tz.TZDateTime.from(localTime, tz.local);
    print('[NotificationService] Created local TZDateTime: $result (timezone: ${tz.local.name})');
    // #region agent log
    _debugLog('notification_service.dart:_localToTZDateTime:RESULT_LOCAL', 'Created TZDateTime.from with local timezone', {
      'localTime': localTime.toString(),
      'tzLocalName': tz.local.name,
      'resultTZDateTime': result.toString(),
      'resultYear': result.year,
      'resultMonth': result.month,
      'resultDay': result.day,
      'resultHour': result.hour,
      'resultMinute': result.minute,
      'resultIsUtc': result.isUtc,
      'resultLocation': result.location.name,
    });
    // #endregion
    return result;
  }

  // Track which notification IDs we're about to schedule to detect duplicates
  static final Set<int> _schedulingIds = <int>{};
  
  static Future<void> scheduleForMedicine(Medicine medicine) async {
    print('[NotificationService] Scheduling notifications for medicine: ${medicine.name} (ID: ${medicine.id})');
    print('[NotificationService] Medicine has ${medicine.schedules.length} schedule(s)');
    
    try {
      // Cancel existing notifications first and wait for completion
      await cancelForMedicine(medicine.id, medicine: medicine);
      print('[NotificationService] Cancelled existing notifications for medicine ${medicine.id}');
      
      // Clear notification ID mappings for this medicine to ensure fresh IDs
      _notificationIdMap.removeWhere((key, _) => key.startsWith('${medicine.id}|'));
      
      // Delay to ensure cancellation completes before scheduling
      // Use longer delay on iOS to avoid hitting system limits
      final delayMs = Platform.isIOS ? 750 : 100;
      await Future.delayed(Duration(milliseconds: delayMs));
      print('[NotificationService] Waited ${delayMs}ms after cancellation before rescheduling (iOS: ${Platform.isIOS})');
      
      int totalNotificationsScheduled = 0;
      int totalNotificationsFailed = 0;
      final Set<int> scheduledIds = <int>{}; // Track IDs scheduled in this call
      
      for (final schedule in medicine.schedules) {
        print('[NotificationService] Processing schedule ${schedule.id}: eye=${schedule.eye.name}, days=${schedule.daysOfWeek}, times=${schedule.times}');
        
        for (final dayOfWeek in schedule.daysOfWeek) {
          for (var ti = 0; ti < schedule.times.length; ti++) {
            final time = schedule.times[ti];
            print('[NotificationService] Processing time slot $ti: $time on day $dayOfWeek');
            
            try {
              final parts = time.split(':');
              final hour = int.parse(parts[0]);
              final minute = parts.length > 1 ? int.parse(parts[1]) : 0;
              
              // Use system local time for date calculations (this gives us the correct local date)
              final systemNow = DateTime.now();
              print('[NotificationService] System local time: $systemNow');
              print('[NotificationService] System date components: year=${systemNow.year}, month=${systemNow.month}, day=${systemNow.day}, weekday=${systemNow.weekday}');
              
              // Create scheduled time using system local time (for correct date)
              // We'll work with DateTime for date logic, then convert to TZDateTime for scheduling
              var scheduledLocal = DateTime(
                systemNow.year,
                systemNow.month,
                systemNow.day,
                hour,
                minute,
              );
              // #region agent log
              _debugLog('notification_service.dart:scheduleForMedicine:CREATED_LOCAL', 'Created scheduledLocal DateTime', {
                'scheduleTime': '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
                'scheduledLocal': scheduledLocal.toString(),
                'scheduledLocalIsUtc': scheduledLocal.isUtc,
                'systemNow': systemNow.toString(),
                'systemNowIsUtc': systemNow.isUtc,
                'systemNowTimezoneOffset': systemNow.timeZoneOffset.toString(),
              });
              // #endregion
              
              // Convert local DateTime to TZDateTime for scheduling
              tz.TZDateTime scheduled = _localToTZDateTime(scheduledLocal);
              // #region agent log
              _debugLog('notification_service.dart:scheduleForMedicine:AFTER_CONVERSION', 'After converting to TZDateTime', {
                'scheduledLocal': scheduledLocal.toString(),
                'scheduledTZDateTime': scheduled.toString(),
                'scheduledYear': scheduled.year,
                'scheduledMonth': scheduled.month,
                'scheduledDay': scheduled.day,
                'scheduledHour': scheduled.hour,
                'scheduledMinute': scheduled.minute,
              });
              // #endregion
              // Use systemNow.weekday for comparison (this is the actual local weekday)
              final todayWeekday = systemNow.weekday;
              print('[NotificationService] Initial scheduled time (local): $scheduledLocal (weekday: $todayWeekday, target weekday: $dayOfWeek)');
              print('[NotificationService] Scheduled date components: year=${scheduledLocal.year}, month=${scheduledLocal.month}, day=${scheduledLocal.day}');
              
              // Check if today matches the target weekday (using system local time)
              if (todayWeekday == dayOfWeek) {
                // Today matches the target weekday
                // Check if scheduled time is in the future (using system local time)
                final timeDifference = scheduledLocal.difference(systemNow);
                if (timeDifference.isNegative) {
                  // Scheduled time has passed - move to next week
                  scheduledLocal = scheduledLocal.add(const Duration(days: 7));
                  // Update TZDateTime accordingly
                  scheduled = _localToTZDateTime(scheduledLocal);
                  print('[NotificationService] Today matches but time passed, moved to next week: $scheduled');
                } else {
                  // Scheduled time is now or in the future - use today
                  print('[NotificationService] Today matches target weekday and time is in future (${timeDifference.inMinutes} minutes from now), scheduling for today');
                  // scheduled already points to today, so we keep it
                }
              } else {
                // Today doesn't match the target weekday - find the next occurrence
                print('[NotificationService] Today (weekday $todayWeekday) does not match target weekday $dayOfWeek, finding next occurrence');
                var nextScheduledLocal = scheduledLocal;
                while (nextScheduledLocal.weekday != dayOfWeek) {
                  nextScheduledLocal = nextScheduledLocal.add(const Duration(days: 1));
                }
                print('[NotificationService] Found next matching weekday: $nextScheduledLocal');
                
                // If the found day/time is in the past, move to next week
                if (nextScheduledLocal.isBefore(systemNow)) {
                  nextScheduledLocal = nextScheduledLocal.add(const Duration(days: 7));
                  print('[NotificationService] Found day was in past, moved to next week: $nextScheduledLocal');
                }
                
                // Update TZDateTime
                scheduledLocal = nextScheduledLocal;
                scheduled = _localToTZDateTime(scheduledLocal);
              }
              
              print('[NotificationService] Final scheduled occurrence: $scheduled');
              print('[NotificationService] Final scheduled occurrence (local): $scheduledLocal');
              
              // Use local date for the payload (not UTC date from TZDateTime)
              final scheduledDateStr = '${scheduledLocal.year}-${scheduledLocal.month.toString().padLeft(2, '0')}-${scheduledLocal.day.toString().padLeft(2, '0')}';
              final payload = jsonEncode({
                'medicineId': medicine.id,
                'scheduleId': schedule.id,
                'eye': schedule.eye.name,
                'scheduledDate': scheduledDateStr,
                'scheduledTime': time,
              });
              print('[NotificationService] Payload: $payload');
              print('[NotificationService] Scheduled date in payload: $scheduledDateStr (from local time: $scheduledLocal)');
              
              // Get user's notification reminder preference
              final reminderPreference = _storage?.getNotificationReminderPreference() ?? const NotificationReminderPreference.defaultValue();
              final selectedReminderMinutes = reminderPreference.enabledReminders;
              
              print('[NotificationService] Reading reminder preference for medicine ${medicine.name}:');
              print('[NotificationService]   - Storage available: ${_storage != null}');
              print('[NotificationService]   - Preference display: ${reminderPreference.displayName}');
              print('[NotificationService]   - Enabled reminders: $selectedReminderMinutes');
              
              // Schedule notifications based on user preference
              // All notifications repeat weekly on the same day of week
              final allNotificationTimes = [
                {'offset': 3, 'minutes': 15, 'message': 'Reminder to take ${medicine.name} in 15 minutes'},
                {'offset': 2, 'minutes': 10, 'message': 'Reminder to take ${medicine.name} in 10 minutes'},
                {'offset': 1, 'minutes': 5, 'message': 'Reminder to take ${medicine.name} in 5 minutes'},
                {'offset': 0, 'minutes': 0, 'message': 'Time to take ${medicine.name}'},
              ];
              
              // Filter to only include selected reminders
              var notificationTimes = allNotificationTimes.where((notif) {
                final minutes = notif['minutes'] as int;
                final offset = notif['offset'] as int;
                // Include reminder if it's in the user's selected preferences
                final shouldInclude = selectedReminderMinutes.contains(minutes);
                if (shouldInclude) {
                  if (offset == 0) {
                    print('[NotificationService]   - Including "at scheduled time" notification (enabled)');
                  } else {
                    print('[NotificationService]   - Including ${minutes} min reminder (enabled)');
                  }
                } else {
                  if (offset == 0) {
                    print('[NotificationService]   - Filtering out "at scheduled time" notification (not enabled)');
                  } else {
                    print('[NotificationService]   - Filtering out ${minutes} min reminder (not enabled)');
                  }
                }
                return shouldInclude;
              }).toList();
              
              // Safety check: ensure at least one notification is included
              if (notificationTimes.isEmpty) {
                print('[NotificationService] ⚠️ WARNING: No notifications enabled! Adding "at scheduled time" notification as fallback.');
                notificationTimes = [allNotificationTimes.firstWhere((n) => n['offset'] == 0)];
              }
              
              print('[NotificationService] Scheduling ${notificationTimes.length} notification(s): ${notificationTimes.map((n) => n['minutes'] == 0 ? 'at scheduled time' : '${n['minutes']} min before').join(', ')}');
              
              for (final notifTime in notificationTimes) {
                final offset = notifTime['offset'] as int;
                final minutesBefore = notifTime['minutes'] as int;
                final message = notifTime['message'] as String;
                
                // Calculate the notification time relative to the scheduled occurrence
                // Calculate in local time first
                final notificationTimeLocal = scheduledLocal.subtract(Duration(minutes: minutesBefore));
                // #region agent log
                _debugLog('notification_service.dart:scheduleForMedicine:NOTIFICATION_TIME_LOCAL', 'Calculated notification time in local', {
                  'scheduledLocal': scheduledLocal.toString(),
                  'minutesBefore': minutesBefore,
                  'notificationTimeLocal': notificationTimeLocal.toString(),
                });
                // #endregion
                
                // Convert to TZDateTime for scheduling
                tz.TZDateTime notificationTime = _localToTZDateTime(notificationTimeLocal);
                // #region agent log
                _debugLog('notification_service.dart:scheduleForMedicine:NOTIFICATION_TIME_TZ', 'Converted notification time to TZDateTime', {
                  'notificationTimeLocal': notificationTimeLocal.toString(),
                  'notificationTimeTZDateTime': notificationTime.toString(),
                  'notificationYear': notificationTime.year,
                  'notificationMonth': notificationTime.month,
                  'notificationDay': notificationTime.day,
                  'notificationHour': notificationTime.hour,
                  'notificationMinute': notificationTime.minute,
                });
                // #endregion
                
                final id = await _getId(medicine.id, schedule.id, dayOfWeek, ti, offset);
                
                // Skip this notification if it's already in the past (using local time comparison)
                final notificationTimeDiff = notificationTimeLocal.difference(systemNow);
                if (notificationTimeDiff.isNegative) {
                  print('[NotificationService] Skipping notification (already in past):');
                  print('  - ID: $id');
                  print('  - Type: ${offset == 0 ? "At scheduled time" : offset == 1 ? "10 min before" : "15 min before"}');
                  print('  - Notification time (local): $notificationTimeLocal');
                  print('  - Current time (local): $systemNow');
                  print('  - Time difference: ${notificationTimeDiff.inMinutes} minutes ago');
                  totalNotificationsFailed++;
                  continue;
                } else {
                  print('[NotificationService] Notification time is in future: $notificationTimeLocal (${notificationTimeDiff.inMinutes} minutes from now)');
                }
                
                // Validate ID is within 32-bit signed integer range
                const max32BitInt = 2147483647;
                if (id > max32BitInt || id < 1) {
                  print('[NotificationService] ✗ ERROR: Notification ID $id is outside valid range (1-$max32BitInt)!');
                  print('[NotificationService]   Components: medicineId=${medicine.id}, scheduleId=${schedule.id}, dayOfWeek=$dayOfWeek, timeIndex=$ti, offset=$offset');
                }
                
                // Check for duplicate IDs within this scheduling call
                if (scheduledIds.contains(id)) {
                  print('[NotificationService] ✗ WARNING: Duplicate ID detected within same scheduling call: $id');
                  print('[NotificationService]   Components: medicineId=${medicine.id}, scheduleId=${schedule.id}, dow=$dayOfWeek, ti=$ti, off=$offset');
                  print('[NotificationService]   This notification will be skipped to avoid duplicates');
                  totalNotificationsFailed++;
                  continue;
                }
                
                // Check if this ID is currently being scheduled by another call
                if (_schedulingIds.contains(id)) {
                  print('[NotificationService] ✗ WARNING: ID $id is already being scheduled by another call');
                  print('[NotificationService]   Waiting for previous scheduling to complete...');
                  // Wait a bit and check again
                  await Future.delayed(const Duration(milliseconds: 100));
                  if (_schedulingIds.contains(id)) {
                    print('[NotificationService] ✗ Skipping duplicate ID $id (still being scheduled)');
                    totalNotificationsFailed++;
                    continue;
                  }
                }
                
                scheduledIds.add(id);
                _schedulingIds.add(id);
                
                print('[NotificationService] Scheduling notification:');
                print('  - ID: $id (medicineId=${medicine.id}, scheduleId=${schedule.id}, dow=$dayOfWeek, ti=$ti, off=$offset)');
                print('  - Type: ${offset == 0 ? "At scheduled time" : offset == 1 ? "10 min before" : "15 min before"}');
                print('  - Message: $message');
                print('  - Notification time (local): $notificationTimeLocal');
                print('  - Notification time (TZDateTime): $notificationTime');
                print('  - Notification time (TZDateTime UTC): ${notificationTime.toUtc()}');
                print('  - Notification time (TZDateTime year/month/day/hour/minute): ${notificationTime.year}/${notificationTime.month}/${notificationTime.day} ${notificationTime.hour}:${notificationTime.minute}');
                print('  - Time until notification: ${notificationTimeDiff.inMinutes} minutes');
                // #region agent log
                _debugLog('notification_service.dart:scheduleForMedicine:BEFORE_ZONED_SCHEDULE', 'About to call zonedSchedule', {
                  'notificationTimeLocal': notificationTimeLocal.toString(),
                  'notificationTimeTZDateTime': notificationTime.toString(),
                  'notificationTimeTZDateTimeUTC': notificationTime.toUtc().toString(),
                  'notificationTimeYear': notificationTime.year,
                  'notificationTimeMonth': notificationTime.month,
                  'notificationTimeDay': notificationTime.day,
                  'notificationTimeHour': notificationTime.hour,
                  'notificationTimeMinute': notificationTime.minute,
                  'notificationTimeIsUtc': notificationTime.isUtc,
                  'notificationTimeLocation': notificationTime.location.name,
                });
                // #endregion
                
                try {
                  await _plugin.zonedSchedule(
                    id,
                    message,
                    'Scheduled: $time',
                    notificationTime,
                    NotificationDetails(
                      android: AndroidNotificationDetails(
                        'thygeson_meds',
                        'Medicine reminders',
                        channelDescription: 'Reminders for scheduled medicine',
                        importance: Importance.high,
                        priority: Priority.high,
                        playSound: true,
                        enableVibration: true,
                        actions: [
                          const AndroidNotificationAction('skip', 'Skip'),
                          const AndroidNotificationAction('taken_on_time', 'Taken on time'),
                          const AndroidNotificationAction('taken_now', 'Taken now'),
                          const AndroidNotificationAction('taken_at_override', 'Taken at...'),
                        ],
                      ),
                      iOS: const DarwinNotificationDetails(
                        presentAlert: true,
                        presentBadge: true,
                        presentSound: true,
                        categoryIdentifier: 'thygeson_meds',
                      ),
                    ),
                    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
                    uiLocalNotificationDateInterpretation:
                        UILocalNotificationDateInterpretation.absoluteTime,
                    matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime, // All repeat weekly
                    payload: payload,
                  );
                  print('[NotificationService] ✓ Successfully scheduled notification ID $id');
                  totalNotificationsScheduled++;
                } catch (e, stackTrace) {
                  print('[NotificationService] ✗ ERROR scheduling notification ID $id: $e');
                  print('[NotificationService] Stack trace: $stackTrace');
                  totalNotificationsFailed++;
                } finally {
                  // Remove from tracking set after scheduling attempt completes
                  _schedulingIds.remove(id);
                }
              }
            } catch (e, stackTrace) {
              print('[NotificationService] ✗ ERROR processing time slot $ti ($time): $e');
              print('[NotificationService] Stack trace: $stackTrace');
              totalNotificationsFailed += 3; // Assume all 3 notifications failed
            }
          }
        }
      }
      
      // Clean up any remaining IDs from tracking (shouldn't happen, but safety check)
      for (final id in scheduledIds) {
        _schedulingIds.remove(id);
      }
      
      print('[NotificationService] Completed scheduling for medicine ${medicine.name}:');
      print('[NotificationService]   - Successfully scheduled: $totalNotificationsScheduled');
      print('[NotificationService]   - Failed: $totalNotificationsFailed');
      print('[NotificationService]   - Unique IDs scheduled: ${scheduledIds.length}');
      
      // Check iOS 64 pending notification limit
      if (Platform.isIOS) {
        try {
          final pending = await _plugin.pendingNotificationRequests();
          print('[NotificationService] iOS pending notifications: ${pending.length}/64');
          if (pending.length > 64) {
            print('[NotificationService] ⚠️ WARNING: iOS has a limit of 64 pending notifications.');
            print('[NotificationService]   You have ${pending.length} scheduled. iOS will silently drop the extras (keeps the 64 soonest).');
            print('[NotificationService]   Consider reducing notification frequency or number of medicines.');
          } else if (pending.length > 50) {
            print('[NotificationService] ⚠️ NOTICE: Approaching iOS 64 notification limit (${pending.length}/64).');
          }
        } catch (e) {
          print('[NotificationService] Could not check pending notification count: $e');
        }
      }
    } catch (e, stackTrace) {
      // Clean up tracking on error - remove all IDs for this medicine
      // Clear notification ID mappings for this medicine (which will also clear associated scheduling IDs)
      final keysToRemove = <String>[];
      for (final entry in _notificationIdMap.entries) {
        if (entry.key.startsWith('${medicine.id}|')) {
          keysToRemove.add(entry.key);
          // Also remove from scheduling set if present
          _schedulingIds.remove(entry.value);
        }
      }
      for (final key in keysToRemove) {
        _notificationIdMap.remove(key);
      }
      print('[NotificationService] ✗ FATAL ERROR scheduling notifications for medicine ${medicine.name}: $e');
      print('[NotificationService] Stack trace: $stackTrace');
      rethrow;
    }
  }

  static Future<void> cancelForMedicine(String medicineId, {Medicine? medicine}) async {
    print('[NotificationService] Cancelling notifications for medicine ID: $medicineId');
    try {
      int cancelledCount = 0;
      int attemptedCount = 0;
      
      // If we have the medicine object, only cancel IDs that could actually exist
      if (medicine != null) {
        print('[NotificationService] Using medicine schedules to cancel only relevant notifications');
        
        // Calculate total notifications to cancel for progress tracking
        int totalToCancel = 0;
        for (final schedule in medicine.schedules) {
          totalToCancel += schedule.daysOfWeek.length * schedule.times.length * 4; // 4 notifications per schedule
        }
        print('[NotificationService] Will attempt to cancel up to $totalToCancel notification(s)');
        
        for (final schedule in medicine.schedules) {
          for (final dayOfWeek in schedule.daysOfWeek) {
            for (var ti = 0; ti < schedule.times.length; ti++) {
              // Cancel all 4 notifications for this schedule (15min, 10min, 5min before, and at time)
              for (var offset = 0; offset < 4; offset++) {
                final key = '$medicineId|${schedule.id}|$dayOfWeek|$ti|$offset';
                final id = _notificationIdMap[key];
                if (id != null) {
                  attemptedCount++;
                  try {
                    await _plugin.cancel(id);
                    cancelledCount++;
                    // Remove from map after successful cancellation
                    _notificationIdMap.remove(key);
                  } catch (e) {
                    // Ignore errors when cancelling (notification may not exist)
                  }
                  
                  // Throttle to avoid Android rate limits (5 cancellations per second)
                  // Delay 250ms after each cancellation to stay well under the limit
                  // Skip delay only on the very last cancellation
                  if (attemptedCount < totalToCancel) {
                    await Future.delayed(const Duration(milliseconds: 250));
                  }
                }
              }
            }
          }
        }
        print('[NotificationService] Cancelled $cancelledCount notification(s) (attempted $attemptedCount IDs based on medicine schedules)');
      } else {
        // Fallback: cancel all possible IDs, but with throttling to avoid rate limits
        print('[NotificationService] WARNING: Medicine object not provided, using fallback cancellation (may be slow)');
        print('[NotificationService] This will attempt to cancel up to ${100 * 7 * 100 * 4} potential IDs');
        
        // Fallback: cancel all notifications for this medicine from our ID map
        // This is less efficient but works when we don't have the medicine object
        final keysToCancel = _notificationIdMap.entries
            .where((entry) => entry.key.startsWith('$medicineId|'))
            .toList();
        
        for (final entry in keysToCancel) {
          attemptedCount++;
          try {
            await _plugin.cancel(entry.value);
            cancelledCount++;
            _notificationIdMap.remove(entry.key);
          } catch (e) {
            // Ignore errors when cancelling (notification may not exist)
          }
          
          // Throttle to avoid Android rate limits (5 cancellations per second)
          // Delay 250ms after each cancellation to stay well under the limit
          // Skip delay only on the very last cancellation
          if (attemptedCount < keysToCancel.length) {
            await Future.delayed(const Duration(milliseconds: 250));
          }
        }
        print('[NotificationService] Cancelled $cancelledCount notification(s) (attempted $attemptedCount IDs with throttling)');
      }
    } catch (e, stackTrace) {
      print('[NotificationService] ✗ ERROR cancelling notifications for medicine $medicineId: $e');
      print('[NotificationService] Stack trace: $stackTrace');
    }
  }

  static Future<void> cancelAll() async {
    print('[NotificationService] Cancelling all notifications...');
    try {
      await _plugin.cancelAll();
      print('[NotificationService] ✓ All notifications cancelled');
    } catch (e, stackTrace) {
      print('[NotificationService] ✗ ERROR cancelling all notifications: $e');
      print('[NotificationService] Stack trace: $stackTrace');
      rethrow;
    }
  }

  static Future<void> addDoseFromOverride(String medicineId, Eye eye, DateTime scheduledDate, String scheduledTime, DateTime takenAt) async {
    await _addDose(medicineId, eye, scheduledDate, scheduledTime, DoseStatus.taken, takenAt);
  }
  
  /// Public method to cancel notifications for a specific schedule when a dose is taken/skipped
  /// This should be called when doses are added from outside the notification service
  static Future<void> cancelForSchedule(String medicineId, DateTime scheduledDate, String scheduledTime, Eye eye) async {
    await _cancelForSchedule(medicineId, scheduledDate, scheduledTime, eye);
  }
  
  /// Reschedule notifications for all medicines (useful after app restart or to fix scheduling issues)
  /// [storage] - Optional storage service to use. If not provided, uses the static storage.
  static Future<void> rescheduleAllNotifications({IStorageService? storage}) async {
    print('[NotificationService] Rescheduling all notifications...');
    final storageToUse = storage ?? _storage;
    if (storageToUse == null) {
      print('[NotificationService] ✗ ERROR: Storage service not set, cannot reschedule');
      return;
    }
    
    print('[NotificationService] Using storage: ${storageToUse.runtimeType}');
    
    // Update static storage so scheduleForMedicine can read the latest preferences
    // This ensures notification preferences are read from the correct storage instance
    if (storage != null) {
      _storage = storageToUse;
      print('[NotificationService] Updated static storage to use provided storage instance');
    }
    
    // Don't cancel all at once - let each scheduleForMedicine handle its own cancellation
    // This avoids potential iOS issues with cancelAll() and provides better control
    // Clear notification ID mappings since we're rescheduling everything
    // Old IDs will be cancelled and new ones will be assigned
    _clearNotificationIdMappings();
    
    final medicines = storageToUse.getMedicines();
    print('[NotificationService] Found ${medicines.length} medicine(s) to reschedule');
    
    if (medicines.isEmpty) {
      print('[NotificationService] ⚠️ WARNING: No medicines found in storage. Cannot reschedule notifications.');
      return;
    }
    
    int successCount = 0;
    int failureCount = 0;
    
    // Add delay between scheduling each medicine on iOS to avoid hitting system limits
    final delayBetweenMedicines = Platform.isIOS ? 500 : 100;
    
    for (var i = 0; i < medicines.length; i++) {
      final medicine = medicines[i];
      try {
        print('[NotificationService] Rescheduling medicine ${i + 1}/${medicines.length}: ${medicine.name} (ID: ${medicine.id})');
        // scheduleForMedicine will cancel existing notifications for this medicine and reschedule
        // It will use the updated _storage to read notification preferences
        await scheduleForMedicine(medicine);
        successCount++;
        print('[NotificationService] ✓ Successfully rescheduled ${medicine.name}');
        
        // Add delay between medicines on iOS to avoid hitting system limits
        // Skip delay after the last medicine
        if (i < medicines.length - 1) {
          await Future.delayed(Duration(milliseconds: delayBetweenMedicines));
        }
      } catch (e, stackTrace) {
        failureCount++;
        print('[NotificationService] ✗ Failed to reschedule medicine ${medicine.name} (ID: ${medicine.id}): $e');
        print('[NotificationService] Stack trace: $stackTrace');
        // Still add delay even on error to maintain spacing
        if (i < medicines.length - 1) {
          await Future.delayed(Duration(milliseconds: delayBetweenMedicines));
        }
      }
    }
    
    print('[NotificationService] Rescheduling complete:');
    print('[NotificationService]   - Successfully rescheduled: $successCount');
    print('[NotificationService]   - Failed: $failureCount');
  }
  
  /// Get all pending notifications from the system (for developer/debugging purposes)
  /// This shows what notifications are actually scheduled in the system
  static Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    try {
      final notifications = await _plugin.pendingNotificationRequests();
      print('[NotificationService] Retrieved ${notifications.length} pending notification(s) from system');
      return notifications;
    } catch (e, stackTrace) {
      print('[NotificationService] ✗ ERROR getting pending notifications: $e');
      print('[NotificationService] Stack trace: $stackTrace');
      rethrow;
    }
  }
  
  /// Fixed ID for test notifications - reusing the same ID cancels any previous test notification
  static const int _testNotificationId = 999999;
  
  /// Schedule a test notification at a specific delay in the future (for testing/debugging)
  /// Uses a fixed ID so re-scheduling replaces any previous test notification
  static Future<void> showTestNotification({Duration delay = const Duration(seconds: 5)}) async {
    print('[NotificationService] Scheduling test notification with delay: ${delay.inSeconds}s...');
    
    try {
      // Cancel any existing test notification first
      await _plugin.cancel(_testNotificationId);
      
      final now = tz.TZDateTime.now(tz.local);
      final scheduledTime = now.add(delay);
      
      print('[NotificationService] Current time: $now');
      print('[NotificationService] Scheduling test notification for: $scheduledTime');
      print('[NotificationService] Time difference: ${delay.inSeconds} seconds');
      
      await _plugin.zonedSchedule(
        _testNotificationId,
        'Test Notification',
        'This is a test notification from the Notification Explorer',
        scheduledTime,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'thygeson_meds',
            'Medicine reminders',
            channelDescription: 'Reminders for scheduled medicine',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            categoryIdentifier: 'thygeson_meds',
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
      print('[NotificationService] ✓ Test notification scheduled for $scheduledTime (ID: $_testNotificationId)');
    } catch (e, stackTrace) {
      print('[NotificationService] ✗ ERROR scheduling test notification: $e');
      print('[NotificationService] Stack trace: $stackTrace');
      rethrow;
    }
  }
  
  /// Check and log notification permission status (for debugging)
  static Future<void> logPermissionStatus() async {
    print('[NotificationService] Checking notification permission status...');
    
    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        try {
          final permissionGranted = await androidPlugin.areNotificationsEnabled();
          print('[NotificationService] Android notifications enabled: $permissionGranted');
        } catch (e) {
          print('[NotificationService] Could not check Android notification status: $e');
        }
      } else {
        print('[NotificationService] Android plugin not available');
      }
    } else if (Platform.isIOS) {
      final iosPlugin = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (iosPlugin != null) {
        try {
          final permissions = await iosPlugin.checkPermissions();
          if (permissions != null) {
            print('[NotificationService] iOS notification permissions: $permissions');
          } else {
            print('[NotificationService] iOS notification permissions: null (not yet requested)');
          }
        } catch (e) {
          print('[NotificationService] Could not check iOS notification status: $e');
        }
      } else {
        print('[NotificationService] iOS plugin not available');
      }
    } else {
      print('[NotificationService] Platform: ${Platform.operatingSystem}');
    }
  }
  
  /// Get reconstructed scheduled notifications from medicine schedules (for comparison)
  /// Note: Recurring notifications with matchDateTimeComponents may not appear in pendingNotificationRequests
  /// So we reconstruct them from medicine schedules
  static Future<List<ScheduledNotificationInfo>> getScheduledNotifications() async {
    final storage = _storage;
    if (storage == null) return [];
    
    final medicines = storage.getMedicines();
    final now = tz.TZDateTime.now(tz.local);
    final List<ScheduledNotificationInfo> notifications = [];
    
    for (final medicine in medicines) {
      for (final schedule in medicine.schedules) {
        for (final dayOfWeek in schedule.daysOfWeek) {
          for (var ti = 0; ti < schedule.times.length; ti++) {
            final time = schedule.times[ti];
            final parts = time.split(':');
            final hour = int.parse(parts[0]);
            final minute = parts.length > 1 ? int.parse(parts[1]) : 0;
            
            // Calculate next scheduled occurrence (same logic as scheduleForMedicine)
            var scheduled = tz.TZDateTime(
              tz.local,
              now.year,
              now.month,
              now.day,
              hour,
              minute,
            );
            while (scheduled.weekday != dayOfWeek) {
              scheduled = scheduled.add(const Duration(days: 1));
            }
            // Only move to next week if the scheduled time itself is in the past
            if (scheduled.isBefore(now)) {
              scheduled = scheduled.add(const Duration(days: 7));
            }
            
            final scheduledDateStr = '${scheduled.year}-${scheduled.month.toString().padLeft(2, '0')}-${scheduled.day.toString().padLeft(2, '0')}';
            final payload = jsonEncode({
              'medicineId': medicine.id,
              'scheduleId': schedule.id,
              'eye': schedule.eye.name,
              'scheduledDate': scheduledDateStr,
              'scheduledTime': time,
            });
            
            // Create info for all 4 notifications
            final notificationTimes = [
              {'offset': 3, 'minutes': 15, 'message': 'Reminder to take ${medicine.name} in 15 minutes'},
              {'offset': 2, 'minutes': 10, 'message': 'Reminder to take ${medicine.name} in 10 minutes'},
              {'offset': 1, 'minutes': 5, 'message': 'Reminder to take ${medicine.name} in 5 minutes'},
              {'offset': 0, 'minutes': 0, 'message': 'Time to take ${medicine.name}'},
            ];
            
            for (final notifTime in notificationTimes) {
              final offset = notifTime['offset'] as int;
              final minutesBefore = notifTime['minutes'] as int;
              final message = notifTime['message'] as String;
              final notificationTime = scheduled.subtract(Duration(minutes: minutesBefore));
              // Look up ID from map, or use 0 if not found (notification may not be scheduled yet)
              final key = '${medicine.id}|${schedule.id}|$dayOfWeek|$ti|$offset';
              final id = _notificationIdMap[key] ?? 0;
              
              notifications.add(ScheduledNotificationInfo(
                id: id,
                title: message,
                body: 'Scheduled: $time',
                payload: payload,
                scheduledTime: notificationTime,
                medicineId: medicine.id,
                medicineName: medicine.name,
                eye: schedule.eye.name,
                scheduledDate: scheduledDateStr,
                scheduledTimeStr: time,
                notificationType: offset == 0 ? 'At scheduled time' : offset == 1 ? '5 min before' : offset == 2 ? '10 min before' : '15 min before',
              ));
            }
          }
        }
      }
    }
    
    // Sort by scheduled time (earliest first)
    notifications.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
    
    return notifications;
  }
}

/// Information about a scheduled notification
class ScheduledNotificationInfo {
  final int id;
  final String title;
  final String body;
  final String payload;
  final tz.TZDateTime scheduledTime;
  final String medicineId;
  final String medicineName;
  final String eye;
  final String scheduledDate;
  final String scheduledTimeStr;
  final String notificationType;

  ScheduledNotificationInfo({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
    required this.scheduledTime,
    required this.medicineId,
    required this.medicineName,
    required this.eye,
    required this.scheduledDate,
    required this.scheduledTimeStr,
    required this.notificationType,
  });
}
