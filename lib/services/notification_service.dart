import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
  // Set by setOnOverrideTimeRequested; invoked when user taps "adjust time" from notification (if wired).
  // ignore: unused_field
  static void Function(String medicineId, String eye, String scheduledDate, String scheduledTime)? _onOverrideTimeRequested;
  static void Function()? _onDoseAdded;
  static void Function(String medicineId, String scheduleId, String eye, String scheduledDate, String scheduledTime)? _onNotificationTapped;
  static NotificationResponse? _pendingLaunchNotification;
  
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
    // If there's a pending launch notification, handle it now that callback is set
    if (_pendingLaunchNotification != null) {
      Future.microtask(() {
        _onNotificationTap(_pendingLaunchNotification!);
        _pendingLaunchNotification = null;
      });
    }
  }

  static Future<void> init() async {
    debugPrint('[NotificationService] Initializing notification service...');
    try {
      tz_data.initializeTimeZones();
      debugPrint('[NotificationService] Timezone data initialized');
      
      // Get the device's actual timezone using flutter_timezone
      final systemNow = DateTime.now();
      debugPrint('[NotificationService] System timezone offset: ${systemNow.timeZoneOffset}');
      
      try {
        final timezoneInfo = await FlutterTimezone.getLocalTimezone();
        final timezoneName = timezoneInfo.identifier;
        debugPrint('[NotificationService] Device timezone (from flutter_timezone): $timezoneName');
        
        final location = tz.getLocation(timezoneName);
        tz.setLocalLocation(location);
        debugPrint('[NotificationService] Set local timezone to: ${tz.local.name}');
      } catch (e) {
        debugPrint('[NotificationService] WARNING: Could not get device timezone: $e');
        // Fallback: try to match by offset (less reliable but better than UTC)
        final offsetHours = systemNow.timeZoneOffset.inHours;
        final offsetMinutes = systemNow.timeZoneOffset.inMinutes % 60;
        debugPrint('[NotificationService] Falling back to offset-based detection: ${offsetHours}h ${offsetMinutes}m');
        
        String? fallbackTimezone;
        if (offsetHours == -5 && offsetMinutes == 0) {
          fallbackTimezone = 'America/New_York';
        } else if (offsetHours == -6 && offsetMinutes == 0) {
          fallbackTimezone = 'America/Chicago';
        } else if (offsetHours == -7 && offsetMinutes == 0) {
          fallbackTimezone = 'America/Denver';
        } else if (offsetHours == -8 && offsetMinutes == 0) {
          fallbackTimezone = 'America/Los_Angeles';
        } else if (offsetHours == 0 && offsetMinutes == 0) {
          fallbackTimezone = 'Europe/London';
        } else if (offsetHours == 1 && offsetMinutes == 0) {
          fallbackTimezone = 'Europe/Paris';
        } else if (offsetHours == 9 && offsetMinutes == 0) {
          fallbackTimezone = 'Asia/Tokyo';
        }
        
        if (fallbackTimezone != null) {
          try {
            tz.setLocalLocation(tz.getLocation(fallbackTimezone));
            debugPrint('[NotificationService] Set fallback timezone to: ${tz.local.name}');
          } catch (e2) {
            debugPrint('[NotificationService] WARNING: Fallback timezone also failed: $e2. Using UTC.');
          }
        } else {
          debugPrint('[NotificationService] WARNING: Unknown timezone offset, using UTC. Notifications may fire at wrong times.');
        }
      }
      
      debugPrint('[NotificationService] System local time: $systemNow');
      debugPrint('[NotificationService] System timezone offset: ${systemNow.timeZoneOffset}');
      debugPrint('[NotificationService] System date: ${systemNow.year}-${systemNow.month.toString().padLeft(2, '0')}-${systemNow.day.toString().padLeft(2, '0')}');
      
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      // Configure iOS to show notifications even when app is in foreground
      final ios = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
        defaultPresentAlert: true, // Show alert when app is in foreground
        defaultPresentSound: true, // Play sound when app is in foreground
        defaultPresentBadge: true, // Update badge when app is in foreground
        defaultPresentBanner: true, // Show banner when app is in foreground (iOS 15+)
        defaultPresentList: true, // Show in notification center when app is in foreground
      );
      final initialized = await _plugin.initialize(
        InitializationSettings(android: android, iOS: ios),
        onDidReceiveNotificationResponse: _onNotificationTap,
      );
      debugPrint('[NotificationService] Plugin initialized: $initialized');
      debugPrint('[NotificationService] Notification tap handler registered');
      
      // #region agent log
      _debugLog('notification_service.dart:init', 'Plugin initialized with tap handler', {
        'initialized': initialized,
        'platform': Platform.operatingSystem,
      });
      // #endregion
      
      // Create notification channel for Android
      if (Platform.isAndroid) {
        debugPrint('[NotificationService] Setting up Android notification channel...');
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
          debugPrint('[NotificationService] Android notification channel created');
          
          final permissionGranted = await androidPlugin.requestNotificationsPermission();
          debugPrint('[NotificationService] Android notification permission granted: $permissionGranted');
          
          // Check exact alarm permission (required for exactAllowWhileIdle on Android 12+)
          try {
            // Note: The plugin may handle this internally, but we log it for debugging
            final areNotificationsEnabled = await androidPlugin.areNotificationsEnabled();
            debugPrint('[NotificationService] Android notifications enabled: $areNotificationsEnabled');
            debugPrint('[NotificationService] Using AndroidScheduleMode.exactAllowWhileIdle - requires SCHEDULE_EXACT_ALARM permission');
            debugPrint('[NotificationService] Note: On Android 12+, user must grant exact alarm permission in system settings');
          } catch (e) {
            debugPrint('[NotificationService] Could not check exact alarm permission status: $e');
          }
        } else {
          debugPrint('[NotificationService] WARNING: Android plugin not available');
        }
      }
      
      // Request notification permissions on iOS
      if (Platform.isIOS) {
        debugPrint('[NotificationService] Requesting iOS notification permissions...');
        final iosPlugin = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
        if (iosPlugin != null) {
          final permissions = await iosPlugin.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
          debugPrint('[NotificationService] iOS notification permissions: $permissions');
        } else {
          debugPrint('[NotificationService] WARNING: iOS plugin not available');
        }
      }
      
      debugPrint('[NotificationService] Initialization complete');
      
      // Handle the case where the app is LAUNCHED from a notification tap
      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp ?? false) {
        final launchResponse = launchDetails?.notificationResponse;
        if (launchResponse != null) {
          debugPrint('[NotificationService] 🔔 App launched from notification tap!');
          // #region agent log
          _debugLog('notification_service.dart:init', 'App launched from notification', {
            'actionId': launchResponse.actionId,
            'notificationId': launchResponse.id,
            'payload': launchResponse.payload,
            'input': launchResponse.input,
          });
          // #endregion
          // Store for later - will be handled once callback is set in app.dart
          _pendingLaunchNotification = launchResponse;
          debugPrint('[NotificationService] Stored launch notification for handling after app initialization');
        }
      }
      
      // Log permission status after initialization
      await logPermissionStatus();
    } catch (e, stackTrace) {
      debugPrint('[NotificationService] ERROR during initialization: $e');
      debugPrint('[NotificationService] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Handle notification tap - logs and triggers callback if set
  static void _onNotificationTap(NotificationResponse response) {
    debugPrint('[NotificationService] ========================================');
    debugPrint('[NotificationService] 🔔 NOTIFICATION TAPPED!');
    debugPrint('[NotificationService] ========================================');
    debugPrint('[NotificationService] actionId: ${response.actionId}');
    debugPrint('[NotificationService] notificationId: ${response.id}');
    debugPrint('[NotificationService] payload: ${response.payload}');
    debugPrint('[NotificationService] input: ${response.input}');
    debugPrint('[NotificationService] ========================================');
    
    // #region agent log
    _debugLog('notification_service.dart:_onNotificationTap', 'Notification tapped', {
      'actionId': response.actionId,
      'notificationId': response.id,
      'payload': response.payload,
      'input': response.input,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    // #endregion
    
    // Parse payload and trigger callback
    try {
      if (response.payload != null) {
        final map = jsonDecode(response.payload!) as Map<String, dynamic>;
        final medicineId = map['medicineId'] as String?;
        final scheduleId = map['scheduleId'] as String?;
        final eyeStr = map['eye'] as String?;
        final scheduledDate = map['scheduledDate'] as String?;
        final scheduledTime = map['scheduledTime'] as String?;
        
        debugPrint('[NotificationService] Parsed payload:');
        debugPrint('[NotificationService]   - medicineId: $medicineId');
        debugPrint('[NotificationService]   - scheduleId: $scheduleId');
        debugPrint('[NotificationService]   - eye: $eyeStr');
        debugPrint('[NotificationService]   - scheduledDate: $scheduledDate');
        debugPrint('[NotificationService]   - scheduledTime: $scheduledTime');
        
        // #region agent log
        _debugLog('notification_service.dart:_onNotificationTap', 'Parsed notification payload', {
          'medicineId': medicineId,
          'scheduleId': scheduleId,
          'eye': eyeStr,
          'scheduledDate': scheduledDate,
          'scheduledTime': scheduledTime,
        });
        // #endregion
        
        // Trigger callback if all required fields are present and callback is set
        if (medicineId != null && scheduleId != null && eyeStr != null && scheduledDate != null && scheduledTime != null) {
          if (_onNotificationTapped != null) {
            debugPrint('[NotificationService] Triggering notification tap callback');
            _onNotificationTapped!(medicineId, scheduleId, eyeStr, scheduledDate, scheduledTime);
          } else {
            debugPrint('[NotificationService] ⚠️ Notification tap callback not set');
          }
        } else {
          debugPrint('[NotificationService] ⚠️ Missing required fields in payload');
        }
      }
    } catch (e) {
      debugPrint('[NotificationService] Could not parse payload: $e');
      // #region agent log
      _debugLog('notification_service.dart:_onNotificationTap', 'Failed to parse payload', {
        'error': e.toString(),
        'payload': response.payload,
      });
      // #endregion
    }
  }

  static Future<void> _addDose(String medicineId, Eye eye, DateTime scheduledDate, String scheduledTime, DoseStatus status, DateTime? takenAt) async {
    final storage = _storage;
    if (storage == null) return;
    final doses = storage.getDoses();
    // Look up medicine name for denormalization
    final medicines = storage.getMedicines();
    final medicine = medicines.firstWhere((m) => m.id == medicineId, orElse: () => Medicine(name: 'Unknown', schedules: [], createdAt: DateTime.now()));
    
    // Reschedule all notifications (cancel all + recreate) when a dose is logged
    await rescheduleAllNotifications(storage: storage);
    
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
  

  /// Notification IDs must fit in 32-bit int (max: 2,147,483,647).
  /// Uses a simple incrementing counter that wraps back to 1 when it reaches the maximum.
  /// Each device maintains its own local counter (not synced across devices).
  /// This method is atomic to prevent duplicate IDs from concurrent calls.
  // ignore: unused_element
  static Future<int> _getNextNotificationId() async {
    // Wait if another ID generation is in progress to prevent race conditions
    while (_idGenerationInProgress) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    
    _idGenerationInProgress = true;
    try {
      final storage = _storage;
      if (storage == null) {
        debugPrint('[NotificationService] WARNING: Storage not available, using default ID 1');
        return 1;
      }
      
      const maxId = 2147483647; // Maximum 32-bit signed integer
      int currentId = storage.getNextNotificationId();
      
      // Increment and wrap if needed
      int nextId = currentId + 1;
      if (nextId > maxId) {
        nextId = 1; // Wrap back to 1
        debugPrint('[NotificationService] Notification ID counter wrapped from $maxId back to 1');
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
  /// This version uses an in-memory counter that must be initialized first.
  // ignore: unused_element
  static int _getIdInMemory(String medicineId, String scheduleId, int dayOfWeek, int timeIndex, int notificationOffset, int Function() getNextId) {
    final key = '$medicineId|$scheduleId|$dayOfWeek|$timeIndex|$notificationOffset';
    
    // Always generate a new ID to ensure uniqueness
    // The map is used for tracking which ID is assigned to which notification for cancellation
    final id = getNextId();
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
    
    debugPrint('[NotificationService] _localToTZDateTime: Converting $localTime (offset: ${localTime.timeZoneOffset})');
    debugPrint('[NotificationService] _localToTZDateTime: Current tz.local.name = ${tz.local.name}');
    
    // If tz.local is still UTC (timezone setting failed), we need to handle it differently
    // The plugin expects TZDateTime in the device's local timezone, not UTC
    if (tz.local.name == 'UTC') {
      debugPrint('[NotificationService] WARNING: tz.local is still UTC, timezone setting may have failed');
      debugPrint('[NotificationService] Creating TZDateTime.utc() and letting plugin handle conversion');
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
      debugPrint('[NotificationService] Created UTC TZDateTime: $result');
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
    debugPrint('[NotificationService] Created local TZDateTime: $result (timezone: ${tz.local.name})');
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
  // Lock to prevent concurrent rescheduling operations
  static bool _reschedulingInProgress = false;
  
  /// Internal method to schedule notifications for a single medicine.
  /// Assumes caller has already locked, cancelled all notifications, and loaded the notification ID counter.
  static Future<void> _scheduleForMedicineInternal(
    Medicine medicine,
    int Function() getNextIdInMemory,
  ) async {
    debugPrint('[NotificationService] Scheduling notifications for medicine: ${medicine.name} (ID: ${medicine.id})');
    debugPrint('[NotificationService] Medicine has ${medicine.schedules.length} schedule(s)');
    
    int totalNotificationsScheduled = 0;
    int totalNotificationsFailed = 0;
    final Set<int> scheduledIds = <int>{}; // Track IDs scheduled in this call
    
    // Clear notification ID mappings for this medicine to ensure fresh IDs
    _notificationIdMap.removeWhere((key, _) => key.startsWith('${medicine.id}|'));
    
    for (final schedule in medicine.schedules) {
        debugPrint('[NotificationService] Processing schedule ${schedule.id}: eye=${schedule.eye.name}, days=${schedule.daysOfWeek}, times=${schedule.times}');
        
        for (final dayOfWeek in schedule.daysOfWeek) {
          for (var ti = 0; ti < schedule.times.length; ti++) {
            final time = schedule.times[ti];
            debugPrint('[NotificationService] Processing time slot $ti: $time on day $dayOfWeek');
            
            try {
              final parts = time.split(':');
              final hour = int.parse(parts[0]);
              final minute = parts.length > 1 ? int.parse(parts[1]) : 0;
              
              // Use system local time for date calculations (this gives us the correct local date)
              final systemNow = DateTime.now();
              debugPrint('[NotificationService] System local time: $systemNow');
              debugPrint('[NotificationService] System date components: year=${systemNow.year}, month=${systemNow.month}, day=${systemNow.day}, weekday=${systemNow.weekday}');
              
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
              debugPrint('[NotificationService] Initial scheduled time (local): $scheduledLocal (weekday: $todayWeekday, target weekday: $dayOfWeek)');
              debugPrint('[NotificationService] Scheduled date components: year=${scheduledLocal.year}, month=${scheduledLocal.month}, day=${scheduledLocal.day}');
              
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
                  debugPrint('[NotificationService] Today matches but time passed, moved to next week: $scheduled');
                } else {
                  // Scheduled time is now or in the future - use today
                  debugPrint('[NotificationService] Today matches target weekday and time is in future (${timeDifference.inMinutes} minutes from now), scheduling for today');
                  // scheduled already points to today, so we keep it
                }
              } else {
                // Today doesn't match the target weekday - find the next occurrence
                debugPrint('[NotificationService] Today (weekday $todayWeekday) does not match target weekday $dayOfWeek, finding next occurrence');
                var nextScheduledLocal = scheduledLocal;
                while (nextScheduledLocal.weekday != dayOfWeek) {
                  nextScheduledLocal = nextScheduledLocal.add(const Duration(days: 1));
                }
                debugPrint('[NotificationService] Found next matching weekday: $nextScheduledLocal');
                
                // If the found day/time is in the past, move to next week
                if (nextScheduledLocal.isBefore(systemNow)) {
                  nextScheduledLocal = nextScheduledLocal.add(const Duration(days: 7));
                  debugPrint('[NotificationService] Found day was in past, moved to next week: $nextScheduledLocal');
                }
                
                // Update TZDateTime
                scheduledLocal = nextScheduledLocal;
                scheduled = _localToTZDateTime(scheduledLocal);
              }
              
              debugPrint('[NotificationService] Final scheduled occurrence: $scheduled');
              debugPrint('[NotificationService] Final scheduled occurrence (local): $scheduledLocal');
              
              // Use local date for the payload (not UTC date from TZDateTime)
              final scheduledDateStr = '${scheduledLocal.year}-${scheduledLocal.month.toString().padLeft(2, '0')}-${scheduledLocal.day.toString().padLeft(2, '0')}';
              final payload = jsonEncode({
                'medicineId': medicine.id,
                'scheduleId': schedule.id,
                'eye': schedule.eye.name,
                'scheduledDate': scheduledDateStr,
                'scheduledTime': time,
              });
              debugPrint('[NotificationService] Payload: $payload');
              debugPrint('[NotificationService] Scheduled date in payload: $scheduledDateStr (from local time: $scheduledLocal)');
              
              // Get user's notification reminder preference
              final reminderPreference = _storage?.getNotificationReminderPreference() ?? const NotificationReminderPreference.defaultValue();
              final selectedReminderMinutes = reminderPreference.enabledReminders;
              
              debugPrint('[NotificationService] Reading reminder preference for medicine ${medicine.name}:');
              debugPrint('[NotificationService]   - Storage available: ${_storage != null}');
              debugPrint('[NotificationService]   - Preference display: ${reminderPreference.displayName}');
              debugPrint('[NotificationService]   - Enabled reminders: $selectedReminderMinutes');
              
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
                    debugPrint('[NotificationService]   - Including "at scheduled time" notification (enabled)');
                  } else {
                    debugPrint('[NotificationService]   - Including $minutes min reminder (enabled)');
                  }
                } else {
                  if (offset == 0) {
                    debugPrint('[NotificationService]   - Filtering out "at scheduled time" notification (not enabled)');
                  } else {
                    debugPrint('[NotificationService]   - Filtering out $minutes min reminder (not enabled)');
                  }
                }
                return shouldInclude;
              }).toList();
              
              // Safety check: ensure at least one notification is included
              if (notificationTimes.isEmpty) {
                debugPrint('[NotificationService] ⚠️ WARNING: No notifications enabled! Adding "at scheduled time" notification as fallback.');
                notificationTimes = [allNotificationTimes.firstWhere((n) => n['offset'] == 0)];
              }
              
              debugPrint('[NotificationService] Scheduling ${notificationTimes.length} notification(s): ${notificationTimes.map((n) => n['minutes'] == 0 ? 'at scheduled time' : '${n['minutes']} min before').join(', ')}');
              
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
                
                final id = getNextIdInMemory();
                final key = '${medicine.id}|${schedule.id}|$dayOfWeek|$ti|$offset';
                _notificationIdMap[key] = id;
                
                // Skip this notification if it's already in the past (using local time comparison)
                final notificationTimeDiff = notificationTimeLocal.difference(systemNow);
                if (notificationTimeDiff.isNegative) {
                  debugPrint('[NotificationService] Skipping notification (already in past):');
                  debugPrint('  - ID: $id');
                  debugPrint('  - Type: ${offset == 0 ? "At scheduled time" : offset == 1 ? "10 min before" : "15 min before"}');
                  debugPrint('  - Notification time (local): $notificationTimeLocal');
                  debugPrint('  - Current time (local): $systemNow');
                  debugPrint('  - Time difference: ${notificationTimeDiff.inMinutes} minutes ago');
                  totalNotificationsFailed++;
                  continue;
                } else {
                  debugPrint('[NotificationService] Notification time is in future: $notificationTimeLocal (${notificationTimeDiff.inMinutes} minutes from now)');
                }
                
                // Validate ID is within 32-bit signed integer range
                const max32BitInt = 2147483647;
                if (id > max32BitInt || id < 1) {
                  debugPrint('[NotificationService] ✗ ERROR: Notification ID $id is outside valid range (1-$max32BitInt)!');
                  debugPrint('[NotificationService]   Components: medicineId=${medicine.id}, scheduleId=${schedule.id}, dayOfWeek=$dayOfWeek, timeIndex=$ti, offset=$offset');
                }
                
                // Check for duplicate IDs within this scheduling call
                if (scheduledIds.contains(id)) {
                  debugPrint('[NotificationService] ✗ WARNING: Duplicate ID detected within same scheduling call: $id');
                  debugPrint('[NotificationService]   Components: medicineId=${medicine.id}, scheduleId=${schedule.id}, dow=$dayOfWeek, ti=$ti, off=$offset');
                  debugPrint('[NotificationService]   This notification will be skipped to avoid duplicates');
                  totalNotificationsFailed++;
                  continue;
                }
                
                // Check if this ID is currently being scheduled by another call
                if (_schedulingIds.contains(id)) {
                  debugPrint('[NotificationService] ✗ WARNING: ID $id is already being scheduled by another call');
                  debugPrint('[NotificationService]   Waiting for previous scheduling to complete...');
                  // Wait a bit and check again
                  await Future.delayed(const Duration(milliseconds: 100));
                  if (_schedulingIds.contains(id)) {
                    debugPrint('[NotificationService] ✗ Skipping duplicate ID $id (still being scheduled)');
                    totalNotificationsFailed++;
                    continue;
                  }
                }
                
                scheduledIds.add(id);
                _schedulingIds.add(id);
                
                debugPrint('[NotificationService] Scheduling notification:');
                debugPrint('  - ID: $id (medicineId=${medicine.id}, scheduleId=${schedule.id}, dow=$dayOfWeek, ti=$ti, off=$offset)');
                debugPrint('  - Type: ${offset == 0 ? "At scheduled time" : offset == 1 ? "10 min before" : "15 min before"}');
                debugPrint('  - Message: $message');
                debugPrint('  - Notification time (local): $notificationTimeLocal');
                debugPrint('  - Notification time (TZDateTime): $notificationTime');
                debugPrint('  - Notification time (TZDateTime UTC): ${notificationTime.toUtc()}');
                debugPrint('  - Notification time (TZDateTime year/month/day/hour/minute): ${notificationTime.year}/${notificationTime.month}/${notificationTime.day} ${notificationTime.hour}:${notificationTime.minute}');
                debugPrint('  - Time until notification: ${notificationTimeDiff.inMinutes} minutes');
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
                      ),
                      iOS: const DarwinNotificationDetails(
                        presentAlert: true,
                        presentBadge: true,
                        presentSound: true,
                      ),
                    ),
                    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
                    uiLocalNotificationDateInterpretation:
                        UILocalNotificationDateInterpretation.absoluteTime,
                    matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime, // All repeat weekly
                    payload: payload,
                  );
                  debugPrint('[NotificationService] ✓ Successfully scheduled notification ID $id');
                  totalNotificationsScheduled++;
                } catch (e, stackTrace) {
                  debugPrint('[NotificationService] ✗ ERROR scheduling notification ID $id: $e');
                  debugPrint('[NotificationService] Stack trace: $stackTrace');
                  totalNotificationsFailed++;
                } finally {
                  // Remove from tracking set after scheduling attempt completes
                  _schedulingIds.remove(id);
                }
              }
            } catch (e, stackTrace) {
              debugPrint('[NotificationService] ✗ ERROR processing time slot $ti ($time): $e');
              debugPrint('[NotificationService] Stack trace: $stackTrace');
              totalNotificationsFailed += 3; // Assume all 3 notifications failed
            }
          }
        }
      }
      
      // Clean up any remaining IDs from tracking (shouldn't happen, but safety check)
      for (final id in scheduledIds) {
        _schedulingIds.remove(id);
      }
      
      debugPrint('[NotificationService] Completed scheduling for medicine ${medicine.name}:');
      debugPrint('[NotificationService]   - Successfully scheduled: $totalNotificationsScheduled');
      debugPrint('[NotificationService]   - Failed: $totalNotificationsFailed');
      debugPrint('[NotificationService]   - Unique IDs scheduled: ${scheduledIds.length}');
  }

  /// Schedule notifications for a medicine.
  /// Always reschedules ALL notifications (cancel all + recreate) for simplicity and consistency.
  /// This ensures no duplicates and handles all edge cases (adding medicine, updating schedules, etc.).
  static Future<void> scheduleForMedicine(
    Medicine medicine, {
    IStorageService? storage,
    List<Medicine>? medicines,
  }) async {
    debugPrint('[NotificationService] Rescheduling all notifications (medicine ${medicine.id} was added/modified)');
    await rescheduleAllNotifications(storage: storage, medicines: medicines);
  }

  /// Cancel notifications for a medicine.
  /// Always reschedules ALL notifications (cancel all + recreate) for simplicity and consistency.
  static Future<void> cancelForMedicine(
    String medicineId, {
    Medicine? medicine,
    IStorageService? storage,
    List<Medicine>? medicines,
  }) async {
    debugPrint('[NotificationService] Rescheduling all notifications (medicine $medicineId was deleted/modified)');
    await rescheduleAllNotifications(storage: storage, medicines: medicines);
  }

  static Future<void> cancelAll() async {
    debugPrint('[NotificationService] Cancelling all notifications...');
    try {
      await _plugin.cancelAll();
      debugPrint('[NotificationService] ✓ All notifications cancelled');
    } catch (e, stackTrace) {
      debugPrint('[NotificationService] ✗ ERROR cancelling all notifications: $e');
      debugPrint('[NotificationService] Stack trace: $stackTrace');
      rethrow;
    }
  }

  static Future<void> addDoseFromOverride(String medicineId, Eye eye, DateTime scheduledDate, String scheduledTime, DateTime takenAt) async {
    await _addDose(medicineId, eye, scheduledDate, scheduledTime, DoseStatus.taken, takenAt);
  }
  
  /// Cancel notifications for a specific schedule.
  /// Always reschedules ALL notifications (cancel all + recreate) for simplicity and consistency.
  static Future<void> cancelForSchedule(
    String medicineId,
    DateTime scheduledDate,
    String scheduledTime,
    Eye eye, {
    IStorageService? storage,
    List<Medicine>? medicines,
  }) async {
    debugPrint('[NotificationService] Rescheduling all notifications (dose logged for medicine $medicineId)');
    await rescheduleAllNotifications(storage: storage, medicines: medicines);
  }
  
  /// Reschedule notifications for all medicines (useful after app restart or to fix scheduling issues)
  /// Uses lock → cancel → schedule → save → unlock pattern.
  /// [storage] - Optional storage service to use. If not provided, uses the static storage.
  static Future<void> rescheduleAllNotifications({
    IStorageService? storage,
    List<Medicine>? medicines,
  }) async {
    // Lock
    if (_reschedulingInProgress) {
      debugPrint('[NotificationService] ⚠️ Rescheduling already in progress, skipping');
      return;
    }
    _reschedulingInProgress = true;
    
    final storageToUse = storage ?? _storage;
    if (storageToUse == null) {
      debugPrint('[NotificationService] ✗ ERROR: Storage service not set, cannot reschedule');
      _reschedulingInProgress = false;
      return;
    }
    
    // Update static storage
    if (storage != null) {
      _storage = storageToUse;
    }
    
    const maxId = 2147483647;
    int currentNotificationId = storageToUse.getNextNotificationId();
    debugPrint('[NotificationService] Loaded notification ID counter: $currentNotificationId');
    
    int getNextIdInMemory() {
      currentNotificationId++;
      if (currentNotificationId > maxId) {
        currentNotificationId = 1;
        debugPrint('[NotificationService] Notification ID counter wrapped from $maxId back to 1');
      }
      return currentNotificationId - 1;
    }
    
    try {
      // Determine which medicines we will schedule.
      // IMPORTANT: If called without an explicit storage (startup timing / storage not wired yet),
      // we do NOT want to cancel everything and then discover 0 medicines.
      final medicinesToSchedule = medicines ?? storageToUse.getMedicines();
      debugPrint('[NotificationService] Rescheduling notifications for ${medicinesToSchedule.length} medicine(s)');

      // If we were called without an explicit storage and we see no medicines, assume the system
      // isn't fully wired yet (e.g. NotificationService.setStorage not called, or wrong instance)
      // and avoid wiping existing scheduled notifications.
      if (medicinesToSchedule.isEmpty && storage == null && medicines == null) {
        debugPrint('[NotificationService] ⚠️ Medicines list is empty (no explicit storage provided). Skipping cancel+reschedule to avoid wiping notifications.');
        return;
      }

      // Cancel all old notifications
      try {
        await _plugin.cancelAll();
        _clearNotificationIdMappings();
        debugPrint('[NotificationService] Cancelled all old notifications');
      } catch (e) {
        // Handle ProGuard/R8 issues in release builds gracefully
        debugPrint('[NotificationService] ⚠️ Error cancelling notifications (non-fatal): $e');
        // Clear mappings anyway to prevent stale state
        _clearNotificationIdMappings();
      }
      
      if (medicinesToSchedule.isEmpty) {
        debugPrint('[NotificationService] No medicines found, nothing to schedule');
        return;
      }
      
      int successCount = 0;
      int failureCount = 0;
    
      // Add delay between scheduling each medicine on iOS to avoid hitting system limits
      final delayBetweenMedicines = Platform.isIOS ? 500 : 100;
      
      for (var i = 0; i < medicinesToSchedule.length; i++) {
        final medicine = medicinesToSchedule[i];
        try {
          debugPrint('[NotificationService] Rescheduling medicine ${i + 1}/${medicinesToSchedule.length}: ${medicine.name} (ID: ${medicine.id})');
          await _scheduleForMedicineInternal(medicine, getNextIdInMemory);
          successCount++;
          debugPrint('[NotificationService] ✓ Successfully rescheduled ${medicine.name}');
          
          // Add delay between medicines on iOS to avoid hitting system limits
          // Skip delay after the last medicine
          if (i < medicinesToSchedule.length - 1) {
            await Future.delayed(Duration(milliseconds: delayBetweenMedicines));
          }
        } catch (e, stackTrace) {
          failureCount++;
          debugPrint('[NotificationService] ✗ Failed to reschedule medicine ${medicine.name} (ID: ${medicine.id}): $e');
          debugPrint('[NotificationService] Stack trace: $stackTrace');
          // Still add delay even on error to maintain spacing
          if (i < medicinesToSchedule.length - 1) {
            await Future.delayed(Duration(milliseconds: delayBetweenMedicines));
          }
        }
      }
      
      // Save notification ID counter
      await storageToUse.setNextNotificationId(currentNotificationId);
      debugPrint('[NotificationService] Saved notification ID counter: $currentNotificationId');
      
      debugPrint('[NotificationService] Rescheduling complete:');
      debugPrint('[NotificationService]   - Successfully rescheduled: $successCount');
      debugPrint('[NotificationService]   - Failed: $failureCount');
    } catch (e, stackTrace) {
      debugPrint('[NotificationService] ✗ ERROR rescheduling all notifications: $e');
      debugPrint('[NotificationService] Stack trace: $stackTrace');
      // Try to save counter even on error
      try {
        await storageToUse.setNextNotificationId(currentNotificationId);
      } catch (_) {}
      rethrow;
    } finally {
      // Unlock
      _reschedulingInProgress = false;
    }
  }
  
  /// Get all pending notifications from the system (for developer/debugging purposes)
  /// This shows what notifications are actually scheduled in the system
  static Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    try {
      final notifications = await _plugin.pendingNotificationRequests();
      debugPrint('[NotificationService] Retrieved ${notifications.length} pending notification(s) from system');
      return notifications;
    } catch (e, stackTrace) {
      debugPrint('[NotificationService] ✗ ERROR getting pending notifications: $e');
      debugPrint('[NotificationService] Stack trace: $stackTrace');
      rethrow;
    }
  }
  
  /// Fixed ID for test notifications - reusing the same ID cancels any previous test notification
  static const int _testNotificationId = 999999;
  
  /// Schedule a test notification at a specific delay in the future (for testing/debugging)
  /// Uses a fixed ID so re-scheduling replaces any previous test notification
  static Future<void> showTestNotification({Duration delay = const Duration(seconds: 5)}) async {
    debugPrint('[NotificationService] Scheduling test notification with delay: ${delay.inSeconds}s...');
    
    try {
      // Cancel any existing test notification first
      await _plugin.cancel(_testNotificationId);
      
      final now = tz.TZDateTime.now(tz.local);
      final scheduledTime = now.add(delay);
      
      debugPrint('[NotificationService] Current time: $now');
      debugPrint('[NotificationService] Scheduling test notification for: $scheduledTime');
      debugPrint('[NotificationService] Time difference: ${delay.inSeconds} seconds');
      
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
      debugPrint('[NotificationService] ✓ Test notification scheduled for $scheduledTime (ID: $_testNotificationId)');
    } catch (e, stackTrace) {
      debugPrint('[NotificationService] ✗ ERROR scheduling test notification: $e');
      debugPrint('[NotificationService] Stack trace: $stackTrace');
      rethrow;
    }
  }
  
  /// Check and log notification permission status (for debugging)
  static Future<void> logPermissionStatus() async {
    debugPrint('[NotificationService] Checking notification permission status...');
    
    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        try {
          final permissionGranted = await androidPlugin.areNotificationsEnabled();
          debugPrint('[NotificationService] Android notifications enabled: $permissionGranted');
        } catch (e) {
          debugPrint('[NotificationService] Could not check Android notification status: $e');
        }
      } else {
        debugPrint('[NotificationService] Android plugin not available');
      }
    } else if (Platform.isIOS) {
      final iosPlugin = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (iosPlugin != null) {
        try {
          final permissions = await iosPlugin.checkPermissions();
          if (permissions != null) {
            debugPrint('[NotificationService] iOS notification permissions: $permissions');
          } else {
            debugPrint('[NotificationService] iOS notification permissions: null (not yet requested)');
          }
        } catch (e) {
          debugPrint('[NotificationService] Could not check iOS notification status: $e');
        }
      } else {
        debugPrint('[NotificationService] iOS plugin not available');
      }
    } else {
      debugPrint('[NotificationService] Platform: ${Platform.operatingSystem}');
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
