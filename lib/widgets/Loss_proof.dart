import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/death_settlement_service.dart';
import '../services/image_service.dart';

/// Proof photos need to stay readable (receipts, vet reports), so they get
/// a larger budget than profile/goat photos. Each photo is its own
/// Firestore document, so ~900 KB still sits under the 1 MiB limit.
const int _proofMaxStoredBytes = 900 * 1024;
const int _proofMaxDimension = 1400;

/// Asks camera vs gallery, then picks and compresses a proof photo with
/// the app's existing [ImageService]. Returns null if the user cancels or
/// the photo can't be used (an error snackbar is shown in that case).
Future<PickedImage?> pickLossProofImage(BuildContext context) async {
  final source = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.of(ctx).pop('camera'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.of(ctx).pop('gallery'),
          ),
        ],
      ),
    ),
  );
  if (source == null) return null;

  try {
    return source == 'camera'
        ? await ImageService.instance.pickFromCamera(
      maxStoredBytes: _proofMaxStoredBytes,
      maxDimension: _proofMaxDimension,
    )
        : await ImageService.instance.pickFromGallery(
      maxStoredBytes: _proofMaxStoredBytes,
      maxDimension: _proofMaxDimension,
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ImageTooLargeException ? e.message : 'Could not use that photo: $e')),
      );
    }
    return null;
  }
}

/// Small thumbnail of a loss record's first proof photo. Tapping opens all
/// of the record's proofs full screen.
class LossProofThumb extends StatelessWidget {
  final String farmId;
  final String lossId;
  final int proofCount;

  const LossProofThumb({
    super.key,
    required this.farmId,
    required this.lossId,
    required this.proofCount,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LossProof>>(
      stream: DeathSettlementService.instance.lossProofsStream(farmId, lossId),
      builder: (context, snapshot) {
        final proofs = snapshot.data ?? const <LossProof>[];
        if (proofs.isEmpty) {
          return const SizedBox(
            height: 90,
            width: 120,
            child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        return InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => LossProofViewer(proofs: proofs)),
          ),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(proofs.first.bytes, height: 90, width: 120, fit: BoxFit.cover),
              ),
              if (proofs.length > 1)
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                    child: Text('+${proofs.length - 1}', style: const TextStyle(color: Colors.white, fontSize: 10)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Full-screen, swipeable, zoomable view of a record's proof photos.
class LossProofViewer extends StatelessWidget {
  final List<LossProof> proofs;

  const LossProofViewer({super.key, required this.proofs});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Proof (${proofs.length})', style: AppTheme.heading(size: 14, color: Colors.white)),
      ),
      body: PageView.builder(
        itemCount: proofs.length,
        itemBuilder: (_, i) => InteractiveViewer(
          child: Center(child: Image.memory(proofs[i].bytes)),
        ),
      ),
    );
  }
}