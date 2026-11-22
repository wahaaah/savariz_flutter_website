class AppointmentBooking {
  const AppointmentBooking({
    required this.appointmentDate,
    required this.appointmentTime,
    this.appointmentEndTime,
    this.purpose,
    this.status,
  });

  final DateTime appointmentDate;
  final String appointmentTime;
  final String? appointmentEndTime;
  final String? purpose;
  final String? status;
}

class AppointmentServiceOption {
  const AppointmentServiceOption({
    required this.name,
    required this.durationMinutes,
  });

  final String name;
  final int durationMinutes;
}

class ClinicClosure {
  const ClinicClosure({
    required this.startDate,
    required this.endDate,
    required this.reason,
    this.startTime,
    this.endTime,
  });

  final DateTime startDate;
  final DateTime endDate;
  final String reason;
  final String? startTime;
  final String? endTime;

  bool includes(DateTime date) {
    final value = DateTime(date.year, date.month, date.day);
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    return !value.isBefore(start) && !value.isAfter(end);
  }
}

class BookingSchedule {
  const BookingSchedule({
    this.bookings = const [],
    this.closures = const [],
    this.services = const [],
  });

  final List<AppointmentBooking> bookings;
  final List<ClinicClosure> closures;
  final List<AppointmentServiceOption> services;
}
