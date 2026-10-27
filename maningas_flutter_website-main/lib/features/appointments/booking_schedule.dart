class AppointmentBooking {
  const AppointmentBooking({
    required this.appointmentDate,
    required this.appointmentTime,
    this.status,
  });

  final DateTime appointmentDate;
  final String appointmentTime;
  final String? status;
}

class ClinicClosure {
  const ClinicClosure({
    required this.startDate,
    required this.endDate,
    required this.reason,
  });

  final DateTime startDate;
  final DateTime endDate;
  final String reason;

  bool includes(DateTime date) {
    final value = DateTime(date.year, date.month, date.day);
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    return !value.isBefore(start) && !value.isAfter(end);
  }
}

class BookingSchedule {
  const BookingSchedule({this.bookings = const [], this.closures = const []});

  final List<AppointmentBooking> bookings;
  final List<ClinicClosure> closures;
}
