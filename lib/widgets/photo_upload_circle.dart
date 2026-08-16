import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Circular photo tile with a small camera badge — the same visual
/// pattern as the Profile farm-photo picker, reused for the Palai
/// "Before Palai" check-in photo upload.
class PhotoUploadCircle extends StatelessWidget {
  final Uint8List? imageBytes;
  final String label;
  final bool isUploading;
  final VoidCallback onTap;
  final double size;

  const PhotoUploadCircle({
    super.key,
    required this.imageBytes,
    required this.label,
    required this.onTap,
    this.isUploading = false,
    this.size = 100,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: AppColors.primaryGreen.withOpacity(0.35), width: 2),
                ),
                child: ClipOval(
                  child: imageBytes != null
                      ? Image.memory(imageBytes!, fit: BoxFit.cover, width: size, height: size)
                      : Icon(Icons.pets, color: AppColors.primaryGreen, size: size * 0.42),
                ),
              ),
              if (isUploading)
                Container(
                  width: size,
                  height: size,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black26),
                  child: const Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                    ),
                  ),
                ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primaryGreen),
                  child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: AppTheme.body(size: 12, weight: FontWeight.w600)),
      ],
    );
  }
}
