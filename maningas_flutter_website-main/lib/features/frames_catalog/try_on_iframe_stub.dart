import 'package:flutter/material.dart';

class TryOnIframe extends StatelessWidget {
  const TryOnIframe({required this.uri, super.key});

  final Uri uri;

  @override
  Widget build(BuildContext context) => const Center(
    child: Text('The virtual Try-On is available in the web portal.'),
  );
}
