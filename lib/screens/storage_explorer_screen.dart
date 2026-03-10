import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/storage_provider.dart';
import '../models/scheduled_dose.dart';
import '../models/medicine_dose.dart';
import '../models/medicine.dart';

class StorageExplorerScreen extends ConsumerStatefulWidget {
  const StorageExplorerScreen({super.key});

  @override
  ConsumerState<StorageExplorerScreen> createState() => _StorageExplorerScreenState();
}

class _StorageExplorerScreenState extends ConsumerState<StorageExplorerScreen> {
  bool _isLoading = true;
  DateTime? _lastRefresh;
  String? _errorMessage;

  // Storage data
  String _medicinesJson = '';
  String _dosesJson = '';
  String _scheduledDosesJson = '';
  String _flareUpsJson = '';
  String _appointmentsJson = '';
  String _preferencesJson = '';
  int _notificationIdCounter = 0;

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<ScheduledDose> _generateScheduledDosesForRange(
    List<Medicine> medicines,
    List<MedicineDose> doses,
  ) {
    final result = <ScheduledDose>[];
    final now = DateTime.now();
    final startDate = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 7));
    final endDate = DateTime(now.year, now.month, now.day).add(const Duration(days: 30));
    
    var currentDate = startDate;
    while (!currentDate.isAfter(endDate)) {
      result.addAll(_generateScheduledDosesForDate(medicines, doses, currentDate));
      currentDate = currentDate.add(const Duration(days: 1));
    }
    
    return result;
  }

  List<ScheduledDose> _generateScheduledDosesForDate(
    List<Medicine> medicines,
    List<MedicineDose> doses,
    DateTime date,
  ) {
    final dayOfWeek = date.weekday; // 1=Mon, 7=Sun
    final result = <ScheduledDose>[];
    final dateStr = DateTime(date.year, date.month, date.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isPastOrToday = !dateStr.isAfter(today);

    // Create a map of medicines by ID for quick lookup
    final medicineById = {for (final m in medicines) m.id: m};
    final addedDoseIds = <String>{};

    // Process existing medicines and generate scheduled doses
    for (final medicine in medicines) {
      final createdDate = DateTime(
        medicine.createdAt.year,
        medicine.createdAt.month,
        medicine.createdAt.day,
      );
      if (dateStr.isBefore(createdDate)) continue;

      for (final schedule in medicine.schedules) {
        if (!schedule.daysOfWeek.contains(dayOfWeek)) continue;

        for (final time in schedule.times) {
          final scheduledDate = dateStr;
          MedicineDose? matchingDose;
          for (final d in doses) {
            if (d.medicineId == medicine.id &&
                d.eye == schedule.eye &&
                d.scheduledDate != null &&
                _sameDay(d.scheduledDate!, scheduledDate) &&
                d.scheduledTime == time) {
              matchingDose = d;
              break;
            }
          }

          ScheduledDoseStatus status;
          DateTime? takenAt;
          if (matchingDose != null) {
            status = matchingDose.status == DoseStatus.taken
                ? ScheduledDoseStatus.taken
                : ScheduledDoseStatus.skipped;
            takenAt = matchingDose.takenAt ?? matchingDose.recordedAt;
            addedDoseIds.add(matchingDose.id);
          } else {
            final parts = time.split(':');
            final scheduledDateTime = DateTime(
              scheduledDate.year,
              scheduledDate.month,
              scheduledDate.day,
              int.parse(parts[0]),
              parts.length > 1 ? int.parse(parts[1]) : 0,
            );
            status = scheduledDateTime.isBefore(DateTime.now())
                ? ScheduledDoseStatus.missed
                : ScheduledDoseStatus.scheduled;
          }

          result.add(ScheduledDose(
            medicineId: medicine.id,
            medicineName: matchingDose?.medicineName ?? medicine.name,
            eye: schedule.eye,
            daysOfWeek: schedule.daysOfWeek,
            times: schedule.times,
            scheduledDate: scheduledDate,
            scheduledTime: time,
            status: status,
            takenAt: takenAt,
            dose: matchingDose,
          ));
        }
      }
    }

    // Add orphaned scheduled doses (from deleted medicines) for past dates and today
    if (isPastOrToday) {
      for (final dose in doses) {
        // Skip if already added or not a scheduled dose
        if (addedDoseIds.contains(dose.id)) continue;
        if (dose.scheduledDate == null || dose.scheduledTime == null) continue;
        
        // Check if this dose is for the date we're looking for
        final doseDate = DateTime(
          dose.scheduledDate!.year,
          dose.scheduledDate!.month,
          dose.scheduledDate!.day,
        );
        if (!_sameDay(doseDate, dateStr)) continue;

        // Check if medicine exists (if not, it's orphaned)
        final medicine = medicineById[dose.medicineId];
        if (medicine == null && dose.medicineName != null) {
          // Orphaned dose - use stored medicine name
          final status = dose.status == DoseStatus.taken
              ? ScheduledDoseStatus.taken
              : ScheduledDoseStatus.skipped;
          // For orphaned doses, we don't have schedule info, so use empty lists
          result.add(ScheduledDose(
            medicineId: dose.medicineId,
            medicineName: dose.medicineName!,
            eye: dose.eye,
            daysOfWeek: [], // Unknown for orphaned doses
            times: [dose.scheduledTime!], // Only know the specific time
            scheduledDate: doseDate,
            scheduledTime: dose.scheduledTime!,
            status: status,
            takenAt: dose.takenAt ?? dose.recordedAt,
            dose: dose,
          ));
        }
      }
    }

    return result;
  }

  @override
  void initState() {
    super.initState();
    _loadStorageData();
  }

  Future<void> _loadStorageData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final storage = ref.read(storageServiceProvider);

      // Load all data structures
      final medicines = storage.getMedicines();
      final doses = storage.getDoses();
      final flareUps = storage.getFlareUps();
      final appointments = storage.getAppointments();
      final notificationId = storage.getNextNotificationId();

      // Get all preferences
      final preferences = storage.getAllPreferences();

      // Generate scheduled doses for a date range (7 days back, 30 days forward)
      final scheduledDoses = _generateScheduledDosesForRange(medicines, doses);

      // Convert to pretty JSON
      final encoder = JsonEncoder.withIndent('  ');
      setState(() {
        _medicinesJson = medicines.isEmpty 
            ? '[]' 
            : encoder.convert(medicines.map((m) => m.toJson()).toList());
        _dosesJson = doses.isEmpty 
            ? '[]' 
            : encoder.convert(doses.map((d) => d.toJson()).toList());
        _scheduledDosesJson = scheduledDoses.isEmpty 
            ? '[]' 
            : encoder.convert(scheduledDoses.map((sd) => sd.toJson()).toList());
        _flareUpsJson = flareUps.isEmpty 
            ? '[]' 
            : encoder.convert(flareUps.map((f) => f.toJson()).toList());
        _appointmentsJson = appointments.isEmpty 
            ? '[]' 
            : encoder.convert(appointments.map((a) => a.toJson()).toList());
        _preferencesJson = preferences.isEmpty 
            ? '{}' 
            : encoder.convert(preferences);
        _notificationIdCounter = notificationId;
        _lastRefresh = DateTime.now();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading storage data: $e';
        _isLoading = false;
      });
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label copied to clipboard'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildSection({
    required String title,
    required String json,
    required IconData icon,
    required Color color,
  }) {
    final isEmpty = json == '[]' || json == '{}' || json.isEmpty;
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ExpansionTile(
        leading: Icon(icon, color: color),
        title: Text(title),
        subtitle: Text(
          isEmpty ? 'Empty' : '${_countItems(json)} item${_countItems(json) == 1 ? '' : 's'}',
          style: TextStyle(
            color: isEmpty ? Colors.grey : null,
            fontSize: 12,
          ),
        ),
        children: [
          if (isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No data',
                style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
              ),
            )
          else
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 400),
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: SelectableText(
                    json,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ),
            ),
          if (!isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy'),
                    onPressed: () => _copyToClipboard(json, title),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  int _countItems(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) return decoded.length;
      if (decoded is Map) return decoded.length;
      return 0;
    } catch (e) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Storage Explorer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStorageData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red[300]),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadStorageData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadStorageData,
                  child: ListView(
                    children: [
                      if (_lastRefresh != null)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Last refreshed: ${_lastRefresh!.toLocal().toString().substring(0, 19)}',
                            style: Theme.of(context).textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      _buildSection(
                        title: 'Medicines',
                        json: _medicinesJson,
                        icon: Icons.medication,
                        color: Colors.blue,
                      ),
                      _buildSection(
                        title: 'Doses',
                        json: _dosesJson,
                        icon: Icons.medication_liquid,
                        color: Colors.green,
                      ),
                      _buildSection(
                        title: 'Scheduled Doses',
                        json: _scheduledDosesJson,
                        icon: Icons.schedule,
                        color: Colors.indigo,
                      ),
                      _buildSection(
                        title: 'Flare-ups',
                        json: _flareUpsJson,
                        icon: Icons.warning,
                        color: Colors.orange,
                      ),
                      _buildSection(
                        title: 'Appointments',
                        json: _appointmentsJson,
                        icon: Icons.calendar_today,
                        color: Colors.purple,
                      ),
                      Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: ListTile(
                          leading: const Icon(Icons.tag, color: Colors.teal),
                          title: const Text('Notification ID Counter'),
                          subtitle: Text('Current value: $_notificationIdCounter'),
                          trailing: IconButton(
                            icon: const Icon(Icons.copy, size: 18),
                            onPressed: () => _copyToClipboard(
                              _notificationIdCounter.toString(),
                              'Notification ID Counter',
                            ),
                          ),
                        ),
                      ),
                      _buildSection(
                        title: 'Preferences',
                        json: _preferencesJson,
                        icon: Icons.settings,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
    );
  }
}
