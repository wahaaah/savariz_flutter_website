abstract interface class AppointmentHistoryRecord {
  String? get id;
  String? get dateValue;
  String? get time;
  String? get purpose;
  String? get status;
  String? get source;
  String? get patientName;
  DateTime? get date;
  DateTime? get scheduledAt;
}

class PatientAppointment implements AppointmentHistoryRecord {
  const PatientAppointment({
    this.id,
    this.dateValue,
    this.time,
    this.purpose,
    this.status,
    this.source,
    this.patientName,
  });

  factory PatientAppointment.fromJson(Map<String, dynamic> json) {
    return PatientAppointment(
      id: _stringOrNumber(json['appointment_id'] ?? json['id']),
      dateValue: _dateOnly(
        json['appointment_date'] ?? json['appointmentDate'] ?? json['date'],
      ),
      time: _timeOnly(
        json['appointment_time'] ?? json['appointmentTime'] ?? json['time'],
      ),
      purpose: _optionalString(
        json['purpose_of_visit'] ??
            json['purposeOfVisit'] ??
            json['reason'] ??
            json['service'],
      ),
      status: _optionalString(
        json['appointment_status'] ??
            json['appointmentStatus'] ??
            json['status'],
      ),
      source: _optionalString(json['appointment_source'] ?? json['source']),
      patientName: _optionalString(
        json['patient_name'] ??
            json['patientName'] ??
            json['full_name'] ??
            json['name'],
      ),
    );
  }

  @override
  final String? id;
  @override
  final String? dateValue;
  @override
  final String? time;
  @override
  final String? purpose;
  @override
  final String? status;
  @override
  final String? source;
  @override
  final String? patientName;

  @override
  DateTime? get date => dateValue == null ? null : DateTime.tryParse(dateValue!);

  @override
  DateTime? get scheduledAt {
    final appointmentDate = date;
    if (appointmentDate == null) return null;
    final appointmentTime = time;
    if (appointmentTime == null) return appointmentDate;
    final parts = appointmentTime.split(':');
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return DateTime(
      appointmentDate.year,
      appointmentDate.month,
      appointmentDate.day,
      hour,
      minute,
    );
  }
}

String? _stringOrNumber(Object? value) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  if (value is num) return value.toString();
  return null;
}

String? _optionalString(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

String? _dateOnly(Object? value) {
  if (value is! String || DateTime.tryParse(value) == null) return null;
  return value.length >= 10 ? value.substring(0, 10) : value;
}

String? _timeOnly(Object? value) {
  if (value is! String) return null;
  final normalized = value.trim();
  if (!RegExp(r'^\d{1,2}:\d{2}(:\d{2})?$').hasMatch(normalized)) {
    return null;
  }
  final pieces = normalized.split(':');
  final hour = int.tryParse(pieces[0]);
  final minute = int.tryParse(pieces[1]);
  if (hour == null || hour > 23 || minute == null || minute > 59) return null;
  return '${hour.toString().padLeft(2, '0')}:${pieces[1]}';
}
