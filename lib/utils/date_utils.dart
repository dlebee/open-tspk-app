/// Adds [days] calendar days to [date]. Uses calendar arithmetic so DST
/// transitions don't skip or duplicate days (unlike adding Duration(days: n)).
DateTime addCalendarDays(DateTime date, int days) {
  return DateTime(date.year, date.month, date.day + days);
}

/// Number of calendar days from [start] to [end] (positive if end is after start).
/// DST-safe: uses UTC date parts so "tomorrow" is always 1 day.
int calendarDaysBetween(DateTime start, DateTime end) {
  final s = DateTime.utc(start.year, start.month, start.day);
  final e = DateTime.utc(end.year, end.month, end.day);
  return e.difference(s).inDays;
}
