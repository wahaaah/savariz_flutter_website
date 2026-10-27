import 'package:flutter/material.dart';

import 'app/theme.dart';
import 'features/profile/edit_profile_page.dart';

void main() {
  runApp(
    MaterialApp(
      title: 'Edit Profile Preview | Gonzales Vision Clinic',
      debugShowCheckedModeBanner: false,
      theme: PatientPortalTheme.light,
      home: const EditProfilePage(),
    ),
  );
}
