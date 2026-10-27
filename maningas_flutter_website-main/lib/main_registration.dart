import 'package:flutter/material.dart';

import 'app/theme.dart';
import 'features/auth/registration_page.dart';

void main() {
  runApp(
    MaterialApp(
      title: 'Create Patient Account | Gonzales Vision Clinic',
      debugShowCheckedModeBanner: false,
      theme: PatientPortalTheme.light,
      home: const RegistrationPage(),
    ),
  );
}
