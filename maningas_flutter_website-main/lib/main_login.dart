import 'package:flutter/material.dart';

import 'app/app.dart';
import 'features/auth/application/patient_auth_setup.dart';

void main() {
  final setup = createPatientAuthSetup();
  runApp(PatientPortalApp(setup: setup));
}
