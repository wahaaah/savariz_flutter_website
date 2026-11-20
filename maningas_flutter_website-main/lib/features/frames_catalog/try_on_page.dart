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
  final _iframeKey = GlobalKey<TryOnIframeState>();

  void _closeTryOn() {
    if (!mounted) return;
    _iframeKey.currentState?.close();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: isDark ? const Color(0xFF0B1220) : const Color(0xFFF8FAFC),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF111827) : Colors.white,
                border: Border(
                  bottom: BorderSide(
                    color: isDark
                        ? const Color(0xFF263449)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '👓 Virtual Try-On',
                      style: TextStyle(
                        color: isDark
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFF0F172A),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Close Try-On',
                    child: IconButton.filled(
                      key: const ValueKey('close-try-on'),
                      tooltip: 'Close Try-On',
                      onPressed: _closeTryOn,
                      style: IconButton.styleFrom(
                        backgroundColor: isDark
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFF1F5F9),
                        foregroundColor: isDark
                            ? const Color(0xFFCBD5E1)
                            : const Color(0xFF64748B),
                        minimumSize: const Size(34, 34),
                        maximumSize: const Size(34, 34),
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.close, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: TryOnIframe(key: _iframeKey, uri: widget.uri),
            ),
          ],
        ),
      ),
    );
  }
}
