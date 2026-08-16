import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Opens a photo full-screen (pinch-to-zoom) with a back button in the
/// top-left corner — used to view the Before Palai / After Palai goat
/// photos at full size from the Check-Out screen.
class FullscreenImageViewer extends StatelessWidget {
  final Uint8List imageBytes;
  final String title;

  const FullscreenImageViewer({
    super.key,
    required this.imageBytes,
    this.title = '',
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: Center(
                  child: Image.memory(imageBytes, fit: BoxFit.contain),
                ),
              ),
            ),
            Positioned(
              top: 6,
              left: 4,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white, size: 26),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            if (title.isNotEmpty)
              Positioned(
                top: 14,
                left: 56,
                right: 16,
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
