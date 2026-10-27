import 'package:flutter/material.dart';

class TryOnIframe extends StatefulWidget {
  const TryOnIframe({required this.uri, super.key});

  final Uri uri;

  @override
  State<TryOnIframe> createState() => TryOnIframeState();
}

class TryOnIframeState extends State<TryOnIframe> {
  void close() {}

  @override
  Widget build(BuildContext context) => const Center(
    child: Text('The virtual Try-On is available in the web portal.'),
  );
}
