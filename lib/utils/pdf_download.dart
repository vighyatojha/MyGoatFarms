import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';

/// Result of [savePdfAs].
class PdfSaveResult {
  const PdfSaveResult._(this.status, [this.fileName]);

  const PdfSaveResult.saved(String name) : this._(PdfSaveStatus.saved, name);
  const PdfSaveResult.cancelled() : this._(PdfSaveStatus.cancelled);
  const PdfSaveResult.shared() : this._(PdfSaveStatus.shared);

  final PdfSaveStatus status;

  /// The name the user saved it as (they can rename it on the save screen).
  final String? fileName;
}

enum PdfSaveStatus { saved, cancelled, shared }

/// Download = "Save as".
///
/// Opens the phone's own save screen (on Android the Files / Google
/// picker): a file-name box the user can change and every place to save
/// to (Downloads, Drive, SD card...). file_picker writes the PDF exactly
/// where they choose, with no storage permission and no native code here.
///
/// Uses the current file_picker API (static FilePicker.saveFile, which
/// returns the saved file's Uri, or null when the user closes the screen).
Future<PdfSaveResult> savePdfAs(Uint8List bytes, String fileName) async {
  Uri? saved;
  try {
    saved = await FilePicker.saveFile(
      dialogTitle: 'Save PDF',
      fileName: fileName,
      bytes: bytes,
      mimeType: 'application/pdf',
    );
  } on UnimplementedError {
    // Platform without a save screen: let the share sheet handle it.
    await Printing.sharePdf(bytes: bytes, filename: fileName);
    return const PdfSaveResult.shared();
  }

  if (saved == null) return const PdfSaveResult.cancelled();
  return PdfSaveResult.saved(_displayName(saved, fileName));
}

/// 'content://.../document/primary%3ADownload%2FBill.pdf' -> 'Bill.pdf'.
String _displayName(Uri uri, String fallback) {
  try {
    final last = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final decoded = Uri.decodeComponent(last);
    final name = decoded.split('/').last.split(':').last.split('\\').last;
    return name.trim().isEmpty ? fallback : name;
  } catch (_) {
    return fallback;
  }
}