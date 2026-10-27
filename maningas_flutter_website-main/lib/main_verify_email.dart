import 'package:flutter/material.dart';

import 'app/theme.dart';
import 'features/auth/verify_email_page.dart';

void main() {
  runApp(
    MaterialApp(
      title: 'Verify Email | Gonzales Vision Clinic',
      debugShowCheckedModeBanner: false,
      theme: PatientPortalTheme.light,
      home: const VerifyEmailPage(),
    ),
  );
}
