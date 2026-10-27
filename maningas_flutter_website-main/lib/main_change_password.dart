import 'package:flutter/material.dart';

import 'app/theme.dart';
import 'features/profile/change_password_page.dart';

void main() {
  runApp(
    MaterialApp(
      title: 'Change Password Preview | Gonzales Vision Clinic',
      debugShowCheckedModeBanner: false,
      theme: PatientPortalTheme.light,
      home: const ChangePasswordPage(),
    ),
  );
}
