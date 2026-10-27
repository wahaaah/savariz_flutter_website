import 'package:flutter/material.dart';

enum PortalDestination {
  dashboard(label: 'Dashboard', icon: Icons.dashboard_outlined),
  appointments(label: 'Appointments', icon: Icons.calendar_month_outlined),
  appointmentHistory(label: 'Appointment History', icon: Icons.history),
  transactionHistory(
    label: 'Transaction History',
    icon: Icons.receipt_long_outlined,
  ),
  framesCatalog(label: 'Frames Catalog', icon: Icons.visibility_outlined),
  supportCenter(label: 'Support Center', icon: Icons.support_agent_outlined),
  profile(label: 'My Profile', icon: Icons.person_outline);

  const PortalDestination({required this.label, required this.icon});

  final String label;
  final IconData icon;
}
