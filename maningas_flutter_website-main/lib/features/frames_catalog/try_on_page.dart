import 'package:flutter/material.dart';

import 'try_on_iframe.dart';

class TryOnPage extends StatefulWidget {
  const TryOnPage({required this.uri, required this.onClose, super.key});

  final Uri uri;
  final VoidCallback onClose;

  @override
  State<TryOnPage> createState() => _TryOnPageState();
}

class _TryOnPageState extends State<TryOnPage> {
  void _closeTryOn() {
    if (mounted) widget.onClose();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black,
    child: SafeArea(
      child: Column(
        children: [
          ColoredBox(
            color: const Color(0xFF111827),
            child: SizedBox(
              height: 56,
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Semantics(
                    button: true,
                    label: 'Close Try-On',
                    child: IconButton.filled(
                      key: const ValueKey('close-try-on'),
                      tooltip: 'Close Try-On',
                      onPressed: _closeTryOn,
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xD9000000),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(48, 48),
                        maximumSize: const Size(48, 48),
                      ),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: TryOnIframe(uri: widget.uri)),
        ],
      ),
    ),
  );
}
