import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Farm-level settings used by the generated/shared bill PDF.
///
/// The old tagline/UPI fields are intentionally kept for backwards
/// compatibility with already-saved Firestore documents or older PDF code,
/// but they are no longer exposed by the Bill Details UI.
class BillSettings {
  final String businessName;
  final String address;
  final String phone;
  final String email;
  final Uint8List? billLogo;
  final String billLogoContentType;
  final String footerNote;

  /// Legacy fields. Do not show/edit these in the UI.
  @Deprecated('Tagline is no longer used by the Bill Details UI.')
  final String tagline;
  @Deprecated('UPI is no longer used by the Bill Details UI.')
  final String upiId;

  /// Legacy free-text terms field. Kept so old data is not lost.
  final String terms;

  /// Structured terms shown as separate numbered sections on the PDF.
  final List<BillTermSection> termsSections;

  /// Optional custom section added after the default terms.
  final String otherTermsTitle;
  final String otherTermsText;
  final bool otherTermsEnabled;

  /// Structured Important Notes shown separately from Terms & Conditions.
  final List<BillNoteSection> importantNotes;

  /// Optional custom note.
  final String otherNoteTitle;
  final String otherNoteText;
  final bool otherNoteEnabled;

  const BillSettings({
    this.businessName = 'My Goat Farms',
    this.address = '',
    this.phone = '',
    this.email = '',
    this.billLogo,
    this.billLogoContentType = 'image/jpeg',
    this.footerNote = 'Thank you for trusting us with your goat.',
    this.tagline = '',
    this.upiId = '',
    this.terms = '',
    this.termsSections = const [],
    this.otherTermsTitle = '',
    this.otherTermsText = '',
    this.otherTermsEnabled = false,
    this.importantNotes = const [],
    this.otherNoteTitle = '',
    this.otherNoteText = '',
    this.otherNoteEnabled = false,
  });

  factory BillSettings.fromMap(
      Map<String, dynamic>? data, {
        String fallbackName = 'My Goat Farms',
        String fallbackAddress = '',
        String fallbackPhone = '',
        String fallbackEmail = '',
      }) {
    String pick(String? value, String fallback) =>
        (value != null && value.trim().isNotEmpty) ? value.trim() : fallback;

    final rawTerms = data?['termsSections'];
    final sections = <BillTermSection>[];
    if (rawTerms is List) {
      for (final item in rawTerms) {
        if (item is Map) {
          sections.add(BillTermSection.fromMap(
            Map<String, dynamic>.from(item),
          ));
        }
      }
    }

    final rawNotes = data?['importantNotes'];
    final notes = <BillNoteSection>[];
    if (rawNotes is List) {
      for (final item in rawNotes) {
        if (item is Map) {
          notes.add(BillNoteSection.fromMap(
            Map<String, dynamic>.from(item),
          ));
        }
      }
    }

    final logoField = data?['billLogo'];

    return BillSettings(
      businessName: pick(data?['businessName'] as String?, fallbackName),
      address: pick(data?['address'] as String?, fallbackAddress),
      phone: pick(data?['phone'] as String?, fallbackPhone),
      email: pick(data?['email'] as String?, fallbackEmail),
      billLogo: logoField is Blob ? logoField.bytes : null,
      billLogoContentType:
      (data?['billLogoContentType'] as String?) ?? 'image/jpeg',
      footerNote: pick(
        data?['footerNote'] as String?,
        'Thank you for trusting us with your goat.',
      ),
      tagline: (data?['tagline'] as String?) ?? '',
      upiId: (data?['upiId'] as String?) ?? '',
      terms: (data?['terms'] as String?) ?? '',
      termsSections: sections.isEmpty ? defaultBillTermSections : sections,
      otherTermsTitle: (data?['otherTermsTitle'] as String?) ?? '',
      otherTermsText: (data?['otherTermsText'] as String?) ?? '',
      otherTermsEnabled: data?['otherTermsEnabled'] == true,
      importantNotes: notes.isEmpty ? defaultBillNoteSections : notes,
      otherNoteTitle: (data?['otherNoteTitle'] as String?) ?? '',
      otherNoteText: (data?['otherNoteText'] as String?) ?? '',
      otherNoteEnabled: data?['otherNoteEnabled'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'businessName': businessName,
      'address': address,
      'phone': phone,
      'email': email,
      'billLogo': billLogo == null ? null : Blob(billLogo!),
      'billLogoContentType': billLogo == null ? null : billLogoContentType,
      'footerNote': footerNote,
      // Keep these fields readable by older builds, but the new UI never edits them.
      'tagline': tagline,
      'upiId': upiId,
      'terms': terms,
      'termsSections': termsSections.map((e) => e.toMap()).toList(),
      'otherTermsTitle': otherTermsTitle,
      'otherTermsText': otherTermsText,
      'otherTermsEnabled': otherTermsEnabled,
      'importantNotes': importantNotes.map((e) => e.toMap()).toList(),
      'otherNoteTitle': otherNoteTitle,
      'otherNoteText': otherNoteText,
      'otherNoteEnabled': otherNoteEnabled,
    };
  }

  BillSettings copyWith({
    String? businessName,
    String? address,
    String? phone,
    String? email,
    Uint8List? billLogo,
    bool removeBillLogo = false,
    String? billLogoContentType,
    String? footerNote,
    String? tagline,
    String? upiId,
    String? terms,
    List<BillTermSection>? termsSections,
    String? otherTermsTitle,
    String? otherTermsText,
    bool? otherTermsEnabled,
    List<BillNoteSection>? importantNotes,
    String? otherNoteTitle,
    String? otherNoteText,
    bool? otherNoteEnabled,
  }) {
    return BillSettings(
      businessName: businessName ?? this.businessName,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      billLogo: removeBillLogo ? null : (billLogo ?? this.billLogo),
      billLogoContentType: billLogoContentType ?? this.billLogoContentType,
      footerNote: footerNote ?? this.footerNote,
      tagline: tagline ?? this.tagline,
      upiId: upiId ?? this.upiId,
      terms: terms ?? this.terms,
      termsSections: termsSections ?? this.termsSections,
      otherTermsTitle: otherTermsTitle ?? this.otherTermsTitle,
      otherTermsText: otherTermsText ?? this.otherTermsText,
      otherTermsEnabled: otherTermsEnabled ?? this.otherTermsEnabled,
      importantNotes: importantNotes ?? this.importantNotes,
      otherNoteTitle: otherNoteTitle ?? this.otherNoteTitle,
      otherNoteText: otherNoteText ?? this.otherNoteText,
      otherNoteEnabled: otherNoteEnabled ?? this.otherNoteEnabled,
    );
  }
}

class BillTermSection {
  final String id;
  final String title;
  final String text;
  final bool enabled;

  const BillTermSection({
    required this.id,
    required this.title,
    required this.text,
    this.enabled = true,
  });

  BillTermSection copyWith({
    String? title,
    String? text,
    bool? enabled,
  }) {
    return BillTermSection(
      id: id,
      title: title ?? this.title,
      text: text ?? this.text,
      enabled: enabled ?? this.enabled,
    );
  }

  factory BillTermSection.fromMap(Map<String, dynamic> map) {
    return BillTermSection(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      text: (map['text'] ?? '').toString(),
      enabled: map['enabled'] != false,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'text': text,
    'enabled': enabled,
  };
}

class BillNoteSection {
  final String id;
  final String title;
  final String text;
  final bool enabled;

  const BillNoteSection({
    required this.id,
    required this.title,
    required this.text,
    this.enabled = true,
  });

  BillNoteSection copyWith({
    String? title,
    String? text,
    bool? enabled,
  }) {
    return BillNoteSection(
      id: id,
      title: title ?? this.title,
      text: text ?? this.text,
      enabled: enabled ?? this.enabled,
    );
  }

  factory BillNoteSection.fromMap(Map<String, dynamic> map) {
    return BillNoteSection(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      text: (map['text'] ?? '').toString(),
      enabled: map['enabled'] != false,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'text': text,
    'enabled': enabled,
  };
}

const defaultBillTermSections = <BillTermSection>[
  BillTermSection(
    id: 'animal-care',
    title: 'Animal Care',
    text:
    'We provide the best care, feeding and shelter for your goats. However, the owner is advised to inform us of any special instructions or medical conditions in advance.',
  ),
  BillTermSection(
    id: 'health-vaccination',
    title: 'Health & Vaccination',
    text:
    'Regular vaccination, deworming and health checkups are done as per the schedule. Any extra medicines or treatment will be charged separately.',
  ),
  BillTermSection(
    id: 'payment-terms',
    title: 'Payment Terms',
    text:
    'Payment should be cleared on or before the next billing date. A late fee may be applicable on overdue amounts.',
  ),
  BillTermSection(
    id: 'liability',
    title: 'Liability',
    text:
    'We are not responsible for any loss or injury due to natural calamities, disease outbreaks or any unforeseen events beyond our control.',
  ),
  BillTermSection(
    id: 'ownership',
    title: 'Ownership',
    text:
    'The goat(s) will always remain the property of the owner. We do not claim any ownership.',
  ),
  BillTermSection(
    id: 'notice',
    title: 'Notice',
    text:
    'Please inform us before taking your goat(s) out from the farm. A minimum notice period is required.',
  ),
];

const defaultBillNoteSections = <BillNoteSection>[
  BillNoteSection(
    id: 'verify',
    title: 'Report Verification',
    text:
    'Please check all details in this report and inform us if any correction is required.',
  ),
  BillNoteSection(
    id: 'records',
    title: 'Records',
    text: 'Keep this report for your records.',
  ),
  BillNoteSection(
    id: 'care',
    title: 'Goat Care',
    text: 'All goats are under our care and supervision.',
  ),
];
