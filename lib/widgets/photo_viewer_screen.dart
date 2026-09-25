import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Full-screen, pinch-to-zoom photo viewer. Opened with a single tap on a
/// stock item's photo — from the Add Medicine form, the Stock list card,
/// or the Stock detail sheet — so any labourer can get a closer look at
/// exactly what the medicine/feed looks like.
class PhotoViewerScreen extends StatelessWidget {
  final Uint8List bytes;
  final String title;

  const PhotoViewerScreen({super.key, required this.bytes, required this.title});

  /// Convenience helper: pushes the viewer as a translucent overlay route.
  static void open(BuildContext context, Uint8List bytes, {String title = ''}) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withOpacity(.92),
        pageBuilder: (_, __, ___) => PhotoViewerScreen(bytes: bytes, title: title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(title.isEmpty ? 'Photo' : title),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4,
          child: Image.memory(bytes),
        ),
      ),
    );
  }
}