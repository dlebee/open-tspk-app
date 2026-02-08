import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/storage_provider.dart';
import '../services/notification_service.dart';

class NotificationExplorerScreen extends ConsumerStatefulWidget {
  const NotificationExplorerScreen({super.key});

  @override
  ConsumerState<NotificationExplorerScreen> createState() => _NotificationExplorerScreenState();
}

class _NotificationExplorerScreenState extends ConsumerState<NotificationExplorerScreen> {
  List<PendingNotificationRequest> _notifications = [];
  bool _isLoading = true;
  DateTime? _lastRefresh;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  /// Extract scheduled DateTime from notification payload
  DateTime? _getScheduledDateTime(PendingNotificationRequest notification) {
    try {
      if (notification.payload != null) {
        final payload = jsonDecode(notification.payload!) as Map<String, dynamic>;
        final scheduledDate = payload['scheduledDate'] as String?;
        final scheduledTime = payload['scheduledTime'] as String?;
        
        if (scheduledDate != null && scheduledTime != null) {
          final dateParts = scheduledDate.split('-');
          final timeParts = scheduledTime.split(':');
          if (dateParts.length == 3 && timeParts.length >= 2) {
            return DateTime(
              int.parse(dateParts[0]),
              int.parse(dateParts[1]),
              int.parse(dateParts[2]),
              int.parse(timeParts[0]),
              int.parse(timeParts[1]),
            );
          }
        }
      }
    } catch (e) {
      // Ignore parsing errors
    }
    return null;
  }

  Future<void> _testNotification(Duration delay) async {
    try {
      await NotificationService.showTestNotification(delay: delay);
      if (mounted) {
        final seconds = delay.inSeconds;
        String message;
        if (seconds < 60) {
          message = 'Test notification scheduled - should appear in $seconds seconds';
        } else {
          final minutes = delay.inMinutes;
          message = 'Test notification scheduled - should appear in $minutes minute${minutes == 1 ? '' : 's'}';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to schedule test notification: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _rescheduleAll() async {
    if (!mounted) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reschedule All Notifications'),
        content: const Text(
          'This will cancel all existing notifications and reschedule them based on your current medicine schedules. '
          'This may take a moment.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reschedule'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Rescheduling notifications...'),
        duration: Duration(seconds: 2),
      ),
    );
    
    try {
      // Use current storage from provider to ensure we have the latest medicines
      final storage = ref.read(storageServiceProvider);
      await NotificationService.rescheduleAllNotifications(storage: storage);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notifications rescheduled successfully'),
            backgroundColor: Colors.green,
          ),
        );
        // Reload notifications to show the updated list
        _loadNotifications();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reschedule: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      // Get actual pending notifications from the system
      final notifications = await NotificationService.getPendingNotifications();
      
      // Sort by scheduled time (nearest first), then by ID as fallback
      final now = DateTime.now();
      notifications.sort((a, b) {
        final aTime = _getScheduledDateTime(a);
        final bTime = _getScheduledDateTime(b);
        
        // If both have scheduled times, sort by time (nearest first)
        if (aTime != null && bTime != null) {
          // Calculate time until notification (negative if in past)
          final aDiff = aTime.difference(now).inMilliseconds;
          final bDiff = bTime.difference(now).inMilliseconds;
          
          // Sort by absolute time difference (nearest first)
          // If both are in the future, sort ascending (nearest first)
          // If both are in the past, sort descending (most recent first)
          // If one is past and one is future, future comes first
          if (aDiff >= 0 && bDiff >= 0) {
            return aDiff.compareTo(bDiff); // Both future: nearest first
          } else if (aDiff < 0 && bDiff < 0) {
            return bDiff.compareTo(aDiff); // Both past: most recent first
          } else {
            return bDiff.compareTo(aDiff); // Future before past
          }
        }
        
        // If only one has a scheduled time, prioritize it
        if (aTime != null && bTime == null) return -1;
        if (aTime == null && bTime != null) return 1;
        
        // Fallback to ID if neither has scheduled time
        return a.id.compareTo(b.id);
      });
      
      setState(() {
        _notifications = notifications;
        _isLoading = false;
        _lastRefresh = DateTime.now();
      });
    } catch (e, stackTrace) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error: $e\n\nStack trace: $stackTrace';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load notifications: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Explorer'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.notification_important),
            tooltip: 'Test Notifications',
            onSelected: (value) {
              if (value == '30s') {
                _testNotification(const Duration(seconds: 30));
              } else if (value == '1m') {
                _testNotification(const Duration(minutes: 1));
              } else if (value == '2m') {
                _testNotification(const Duration(minutes: 2));
              } else if (value == '3m') {
                _testNotification(const Duration(minutes: 3));
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: '30s',
                child: Row(
                  children: [
                    Icon(Icons.timer, size: 20),
                    SizedBox(width: 8),
                    Text('Test in 30 seconds'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: '1m',
                child: Row(
                  children: [
                    Icon(Icons.timer, size: 20),
                    SizedBox(width: 8),
                    Text('Test in 1 minute'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: '2m',
                child: Row(
                  children: [
                    Icon(Icons.timer, size: 20),
                    SizedBox(width: 8),
                    Text('Test in 2 minutes'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: '3m',
                child: Row(
                  children: [
                    Icon(Icons.timer, size: 20),
                    SizedBox(width: 8),
                    Text('Test in 3 minutes'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadNotifications,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.schedule),
            onPressed: _rescheduleAll,
            tooltip: 'Reschedule All Notifications',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        const Text(
                          'Error loading notifications',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage!,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                          textAlign: TextAlign.left,
                        ),
                      ],
                    ),
                  ),
                )
          : _notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.notifications_off, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text(
                        'No scheduled notifications found',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'The system reports no pending notifications.',
                        style: TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _lastRefresh != null
                            ? 'Last refreshed: ${DateFormat('HH:mm:ss').format(_lastRefresh!)}'
                            : '',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      child: Column(
                        children: [
                          Text(
                            'Total: ${_notifications.length} notification${_notifications.length == 1 ? '' : 's'}',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (_lastRefresh != null)
                            Text(
                              'Last refreshed: ${DateFormat('HH:mm:ss').format(_lastRefresh!)}',
                              style: Theme.of(context).textTheme.bodySmall,
                              textAlign: TextAlign.center,
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _notifications.length,
                        padding: const EdgeInsets.all(8),
                        itemBuilder: (context, index) {
                          final notification = _notifications[index];
                          return _NotificationCard(notification: notification);
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final PendingNotificationRequest notification;

  const _NotificationCard({required this.notification});

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? payload;
    String? medicineId;
    String? eye;
    String? scheduledDate;
    String? scheduledTime;
    DateTime? parsedScheduledTime;
    DateTime? notificationTriggerTime; // When this specific notification fires
    Duration? timeUntil;

    try {
      if (notification.payload != null) {
        payload = jsonDecode(notification.payload!) as Map<String, dynamic>;
        medicineId = payload['medicineId'] as String?;
        eye = payload['eye'] as String?;
        scheduledDate = payload['scheduledDate'] as String?;
        scheduledTime = payload['scheduledTime'] as String?;
        
        if (scheduledDate != null && scheduledTime != null) {
          final dateParts = scheduledDate.split('-');
          final timeParts = scheduledTime.split(':');
          if (dateParts.length == 3 && timeParts.length >= 2) {
            parsedScheduledTime = DateTime(
              int.parse(dateParts[0]),
              int.parse(dateParts[1]),
              int.parse(dateParts[2]),
              int.parse(timeParts[0]),
              int.parse(timeParts[1]),
            );
            
            // Determine how many minutes before the scheduled time this notification fires
            int minutesBefore = 0;
            final title = notification.title ?? '';
            if (title.contains('15 minutes') || title.contains('in 15 minutes')) {
              minutesBefore = 15;
            } else if (title.contains('10 minutes') || title.contains('in 10 minutes')) {
              minutesBefore = 10;
            } else if (title.contains('5 minutes') || title.contains('in 5 minutes')) {
              minutesBefore = 5;
            }
            // If minutesBefore is 0, it's the "at scheduled time" notification
            
            // Calculate when this notification actually fires
            notificationTriggerTime = parsedScheduledTime.subtract(Duration(minutes: minutesBefore));
            
            final now = DateTime.now();
            if (notificationTriggerTime.isAfter(now)) {
              timeUntil = notificationTriggerTime.difference(now);
            }
          }
        }
      }
    } catch (e) {
      // Ignore parsing errors, but payload might be malformed
    }

    // Determine notification type based on title
    String notificationType = 'Unknown';
    if (notification.title?.contains('15 minutes') == true || notification.title?.contains('in 15 minutes') == true) {
      notificationType = '15 min before';
    } else if (notification.title?.contains('10 minutes') == true || notification.title?.contains('in 10 minutes') == true) {
      notificationType = '10 min before';
    } else if (notification.title?.contains('5 minutes') == true || notification.title?.contains('in 5 minutes') == true) {
      notificationType = '5 min before';
    } else if (notification.title?.contains('Time to take') == true || notification.title?.contains(' - ') == true) {
      notificationType = 'At scheduled time';
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Text(
            '${notification.id}',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        title: Text(
          notification.title ?? 'No title',
          style: const TextStyle(fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              notification.body ?? 'No body',
              overflow: TextOverflow.ellipsis,
            ),
            if (parsedScheduledTime != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.schedule, size: 14, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Dose scheduled: ${DateFormat('MMM d, y • HH:mm').format(parsedScheduledTime)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            if (notificationTriggerTime != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.notifications_active, size: 14, color: Colors.blue),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Notification fires: ${DateFormat('MMM d, y • HH:mm').format(notificationTriggerTime)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.blue,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            if (timeUntil != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.access_time, size: 14, color: Colors.green),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Time until notification: ${_formatDuration(timeUntil)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.green,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(label: 'Notification ID', value: '${notification.id}'),
                _InfoRow(label: 'Type', value: notificationType),
                if (medicineId != null)
                  _InfoRow(label: 'Medicine ID', value: medicineId),
                if (eye != null) _InfoRow(label: 'Eye', value: eye),
                if (scheduledDate != null)
                  _InfoRow(label: 'Scheduled Date', value: scheduledDate),
                if (scheduledTime != null)
                  _InfoRow(label: 'Scheduled Time', value: scheduledTime),
                if (parsedScheduledTime != null)
                  _InfoRow(label: 'Parsed DateTime', value: DateFormat('yyyy-MM-dd HH:mm:ss').format(parsedScheduledTime)),
                const SizedBox(height: 8),
                const Text(
                  'Raw Data:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                _InfoRow(label: 'Title', value: notification.title ?? '(null)'),
                _InfoRow(label: 'Body', value: notification.body ?? '(null)'),
                if (notification.payload != null) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Payload:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      notification.payload!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ] else
                  const Text(
                    'No payload',
                    style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.inDays > 0) {
      return '${duration.inDays}d ${duration.inHours % 24}h ${duration.inMinutes % 60}m';
    } else if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    } else {
      return '${duration.inMinutes}m';
    }
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}
