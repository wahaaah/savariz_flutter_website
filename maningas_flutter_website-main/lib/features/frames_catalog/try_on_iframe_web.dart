import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class TryOnIframe extends StatefulWidget {
  const TryOnIframe({required this.uri, super.key});

  final Uri uri;

  @override
  State<TryOnIframe> createState() => _TryOnIframeState();
}

class _TryOnIframeState extends State<TryOnIframe> {
  web.HTMLIFrameElement? _iframe;

  void _configureIframe(Object element) {
    final iframe = element as web.HTMLIFrameElement;
    _iframe = iframe;
    iframe.title = 'Virtual Try-On camera';
    iframe.allow = 'camera';
    iframe.style
      ..border = '0'
      ..width = '100%'
      ..height = '100%';
    iframe.src = widget.uri.toString();
  }

  @override
  void dispose() {
    final iframe = _iframe;
    if (iframe != null) {
      iframe.src = 'about:blank';
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
    tagName: 'iframe',
    onElementCreated: _configureIframe,
  );
}
