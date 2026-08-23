import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

/// The two kinds of Palai report the owner can generate for a goat.
///
/// [progress] summarizes everything recorded from the goat's check-in
/// (registration) date up to today — weight trend, latest health update,
/// and photos captured for this report. [final_] is meant to be
/// generated once the goat is checked out, with a complete before/after
/// summary; that logic isn't built yet, so picking it in Generate Report
/// just shows a "coming soon" message instead of generating anything.
enum GoatReportType { progress, final_ }

extension GoatReportTypeX on GoatReportType {
  String get label => this == GoatReportType.progress ? 'Progress Report' : 'Final Report';

  /// Value stored on Firestore documents for this type.
  String get storageValue => this == GoatReportType.progress ? 'progress' : 'final';

  /// Shown as the goat's `reportStatus` badge once a report of this type
  /// has been generated.
  String get statusLabel => this == GoatReportType.progress ? 'Progress Report Generated' : 'Final Report Generated';

  static GoatReportType fromStorage(String? value) {
    return value == 'final' ? GoatReportType.final_ : GoatReportType.progress;
  }
}

/// A single photo shown in a generated report. Stored as a Firestore
/// `Blob` inside the [GoatReport] document, the same pattern the app
/// already uses for the goat's Before/After Palai photos.
///
/// A report can carry photos from three different moments in the
/// goat's stay — [label] is what tells them apart in the PDF (e.g.
/// "Check-In Photo", "Health Update Photo", "Report Day Photo"):
///   1. The photo taken at check-in (goat's `beforeImage`).
///   2. The photo attached to the most recent health record.
///   3. Photo(s) captured fresh while generating this report.
class ReportImage {
  final Uint8List bytes;
  final String contentType;
  final String label;
  const ReportImage({required this.bytes, required this.contentType, this.label = ''});
}

/// A report generated for one goat, covering [fromDate] (the goat's
/// check-in / registration date) through [toDate] (the day it was
/// generated). Every report generated is kept on record under the goat
/// (`.../goats/{goatId}/reports/{reportId}`) and drives the "Report"
/// status badge shown on the goat card in Goats in Palai.
class GoatReport {
  final String id;
  final GoatReportType type;
  final DateTime fromDate;
  final DateTime toDate;
  final DateTime generatedAt;
  final double? startWeight;
  final double? endWeight;
  final String healthStatus;
  final String notes;
  final List<ReportImage> images;

  GoatReport({
    required this.id,
    required this.type,
    required this.fromDate,
    required this.toDate,
    required this.generatedAt,
    this.startWeight,
    this.endWeight,
    required this.healthStatus,
    this.notes = '',
    this.images = const [],
  });

  factory GoatReport.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final rawImages = (data['reportImages'] as List<dynamic>?) ?? const [];
    return GoatReport(
      id: doc.id,
      type: GoatReportTypeX.fromStorage(data['type'] as String?),
      fromDate: (data['fromDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      toDate: (data['toDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      generatedAt: (data['generatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      startWeight: (data['startWeight'] as num?)?.toDouble(),
      endWeight: (data['endWeight'] as num?)?.toDouble(),
      healthStatus: data['healthStatus'] as String? ?? '',
      notes: data['notes'] as String? ?? '',
      images: rawImages.whereType<Map<String, dynamic>>().map((m) {
        final field = m['bytes'];
        return ReportImage(
          bytes: field is Blob ? field.bytes : Uint8List(0),
          contentType: m['contentType'] as String? ?? 'image/jpeg',
          label: m['label'] as String? ?? '',
        );
      }).where((img) => img.bytes.isNotEmpty).toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type.storageValue,
      'fromDate': Timestamp.fromDate(fromDate),
      'toDate': Timestamp.fromDate(toDate),
      'generatedAt': FieldValue.serverTimestamp(),
      'startWeight': startWeight,
      'endWeight': endWeight,
      'healthStatus': healthStatus,
      'notes': notes,
      'reportImages': images
          .map((img) => {
        'bytes': Blob(img.bytes),
        'contentType': img.contentType,
        'label': img.label,
      })
          .toList(),
    };
  }
}