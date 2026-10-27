import 'package:flutter/material.dart';

import 'app/theme.dart';
import 'features/auth/forgot_password_page.dart';

void main() {
  runApp(
    MaterialApp(
      title: 'Forgot Password | Gonzales Vision Clinic',
      debugShowCheckedModeBanner: false,
      theme: PatientPortalTheme.light,
      home: const ForgotPasswordPage(),
    ),
  );
}
