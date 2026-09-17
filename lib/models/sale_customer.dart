import 'package:cloud_firestore/cloud_firestore.dart';

/// ============================================================================
/// SALE CUSTOMER
/// ============================================================================
///
/// Represents a *buyer* in the Trading / Sale flow — someone the farm sells
/// goats to. This is intentionally a separate model/collection from
/// [PalaiCustomer] (`farms/{farmId}/palaiCustomers`), which represents a
/// boarding customer whose goats are cared for under a Palai package.
///
/// WHY A SEPARATE COLLECTION:
/// A one-off buyer ("Deliver Now" sale) is not a boarding customer — they
/// have no package, no joining date, and should never be counted in the
/// Palai pending-payments dashboard. Reusing `palaiCustomers` for Sale
/// buyers would force fake package/joining-date values onto every buyer
/// and silently pollute that dashboard's totals.
///
/// Stored at:
/// farms/{farmId}/customers_own_palai/{customerId}
///
/// DYNAMIC SOURCE:
/// A Sale customer can come from one of two places, tracked by [source]:
/// - [sourceManual]: created fresh, just for Sale.
/// - [sourcePalai]: the person picked an existing Palai (boarding) customer
///   as the buyer. In that case [linkedPalaiCustomerId] points back at the
///   `palaiCustomers` doc this record was created from, and the identity
///   fields below are a denormalized snapshot of that customer at the time
///   of linking (kept in sync only when the person re-links; not live).
///
/// This model does NOT write into `palaiCustomers`. Only an explicit
/// "Transfer to Palai" action (a later Sale-wizard branch) creates/links a
/// `palaiCustomers` doc — this model only reads from it, once, to seed a
/// Sale customer record.
/// ============================================================================

class SaleCustomer {
  final String id;

  // --------------------------------------------------------------------------
  // Identity
  // --------------------------------------------------------------------------

  final String name;
  final String mobileNumber;
  final String alternateMobileNumber;
  final String address;
  final String notes;

  // --------------------------------------------------------------------------
  // Source (dynamic: manual vs linked from Palai)
  // --------------------------------------------------------------------------

  /// One of [sourceManual] or [sourcePalai].
  final String source;

  /// Set only when [source] == [sourcePalai]. Points at the
  /// `farms/{farmId}/palaiCustomers/{id}` doc this Sale customer was
  /// created from, so the two records can be cross-referenced later.
  final String? linkedPalaiCustomerId;

  // --------------------------------------------------------------------------
  // Sale Summary (denormalized, updated as sales complete)
  // --------------------------------------------------------------------------

  final int totalPurchases;
  final int totalGoatsPurchased;
  final double totalSpent;

  // --------------------------------------------------------------------------
  // Audit
  // --------------------------------------------------------------------------

  final DateTime createdAt;
  final DateTime updatedAt;

  // ==========================================================================
  // CONSTANTS
  // ==========================================================================

  static const String sourceManual = 'manual';
  static const String sourcePalai = 'palai';

  static const List<String> sourceValues = [
    sourceManual,
    sourcePalai,
  ];

  // ==========================================================================
  // CONSTRUCTOR
  // ==========================================================================

  const SaleCustomer({
    required this.id,
    required this.name,
    required this.mobileNumber,
    this.alternateMobileNumber = '',
    this.address = '',
    this.notes = '',
    this.source = sourceManual,
    this.linkedPalaiCustomerId,
    this.totalPurchases = 0,
    this.totalGoatsPurchased = 0,
    this.totalSpent = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  // ==========================================================================
  // COPY WITH
  // ==========================================================================

  SaleCustomer copyWith({
    String? id,
    String? name,
    String? mobileNumber,
    String? alternateMobileNumber,
    String? address,
    String? notes,
    String? source,
    String? linkedPalaiCustomerId,
    bool clearLinkedPalaiCustomerId = false,
    int? totalPurchases,
    int? totalGoatsPurchased,
    double? totalSpent,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SaleCustomer(
      id: id ?? this.id,
      name: name ?? this.name,
      mobileNumber: mobileNumber ?? this.mobileNumber,
      alternateMobileNumber:
      alternateMobileNumber ?? this.alternateMobileNumber,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      source: source ?? this.source,
      linkedPalaiCustomerId: clearLinkedPalaiCustomerId
          ? null
          : (linkedPalaiCustomerId ?? this.linkedPalaiCustomerId),
      totalPurchases: totalPurchases ?? this.totalPurchases,
      totalGoatsPurchased: totalGoatsPurchased ?? this.totalGoatsPurchased,
      totalSpent: totalSpent ?? this.totalSpent,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // ==========================================================================
  // FIRESTORE -> MODEL
  // ==========================================================================

  factory SaleCustomer.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? <String, dynamic>{};

    return SaleCustomer(
      id: doc.id,
      name: _stringValue(data['name']),
      mobileNumber: _stringValue(data['mobileNumber']),
      alternateMobileNumber: _stringValue(data['alternateMobileNumber']),
      address: _stringValue(data['address']),
      notes: _stringValue(data['notes']),
      source: _sourceValue(data['source']),
      linkedPalaiCustomerId: _nullableStringValue(
        data['linkedPalaiCustomerId'],
      ),
      totalPurchases: _intValue(data['totalPurchases']),
      totalGoatsPurchased: _intValue(data['totalGoatsPurchased']),
      totalSpent: _doubleValue(data['totalSpent']),
      createdAt: _dateValue(data['createdAt']),
      updatedAt: _dateValue(data['updatedAt']),
    );
  }

  // ==========================================================================
  // MODEL -> FIRESTORE
  // ==========================================================================

  Map<String, dynamic> toMap({
    bool useServerTimestamps = false,
  }) {
    return {
      'name': name,
      'mobileNumber': mobileNumber,
      'alternateMobileNumber': alternateMobileNumber,
      'address': address,
      'notes': notes,
      'source': source,
      'linkedPalaiCustomerId': linkedPalaiCustomerId,
      'totalPurchases': totalPurchases,
      'totalGoatsPurchased': totalGoatsPurchased,
      'totalSpent': totalSpent,
      if (useServerTimestamps)
        'createdAt': FieldValue.serverTimestamp()
      else
        'createdAt': Timestamp.fromDate(createdAt),
      if (useServerTimestamps)
        'updatedAt': FieldValue.serverTimestamp()
      else
        'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  // ==========================================================================
  // EMPTY / NEW CUSTOMER (manual creation)
  // ==========================================================================

  factory SaleCustomer.empty({
    required String id,
  }) {
    final now = DateTime.now();

    return SaleCustomer(
      id: id,
      name: '',
      mobileNumber: '',
      alternateMobileNumber: '',
      address: '',
      notes: '',
      source: sourceManual,
      linkedPalaiCustomerId: null,
      totalPurchases: 0,
      totalGoatsPurchased: 0,
      totalSpent: 0,
      createdAt: now,
      updatedAt: now,
    );
  }

  // ==========================================================================
  // SEED FROM AN EXISTING PALAI CUSTOMER
  // ==========================================================================
  //
  // Builds a denormalized Sale customer snapshot from a Palai customer's
  // identity fields, when the person chooses "Use existing Palai customer"
  // instead of creating a new one. `id` should be a fresh Firestore doc id
  // (the caller is responsible for checking whether a Sale customer linked
  // to this Palai customer already exists — see
  // SaleCustomerService.getOrCreateFromPalaiCustomer).
  //
  // Only identity fields are copied. Financial fields (pendingAmount,
  // advanceAmount) belong to the Palai record and are NOT copied here —
  // this record tracks Sale totals only, kept separate on purpose.

  factory SaleCustomer.fromPalaiCustomerFields({
    required String id,
    required String palaiCustomerId,
    required String name,
    required String mobileNumber,
    String alternateMobileNumber = '',
    String address = '',
  }) {
    final now = DateTime.now();

    return SaleCustomer(
      id: id,
      name: name,
      mobileNumber: mobileNumber,
      alternateMobileNumber: alternateMobileNumber,
      address: address,
      notes: '',
      source: sourcePalai,
      linkedPalaiCustomerId: palaiCustomerId,
      totalPurchases: 0,
      totalGoatsPurchased: 0,
      totalSpent: 0,
      createdAt: now,
      updatedAt: now,
    );
  }

  // ==========================================================================
  // DISPLAY HELPERS
  // ==========================================================================

  String get displayName {
    if (name.trim().isEmpty) {
      return 'Unnamed Customer';
    }
    return name.trim();
  }

  bool get isFromPalai => source == sourcePalai;

  bool get isManual => source == sourceManual;

  bool get hasPurchases => totalPurchases > 0;

  // ==========================================================================
  // VALIDATION
  // ==========================================================================

  String? validate() {
    if (name.trim().isEmpty) {
      return 'Customer name is required.';
    }

    if (mobileNumber.trim().isEmpty) {
      return 'Mobile number is required.';
    }

    if (!sourceValues.contains(source)) {
      return 'Invalid customer source.';
    }

    if (source == sourcePalai &&
        (linkedPalaiCustomerId == null ||
            linkedPalaiCustomerId!.trim().isEmpty)) {
      return 'A Palai-linked customer must reference a Palai customer.';
    }

    if (totalPurchases < 0) {
      return 'Total purchases cannot be negative.';
    }

    if (totalGoatsPurchased < 0) {
      return 'Total goats purchased cannot be negative.';
    }

    if (totalSpent < 0) {
      return 'Total spent cannot be negative.';
    }

    return null;
  }

  // ==========================================================================
  // PRIVATE PARSING HELPERS
  // ==========================================================================

  static String _stringValue(dynamic value) {
    if (value == null) return '';
    return value.toString();
  }

  static String? _nullableStringValue(dynamic value) {
    if (value == null) return null;
    final result = value.toString().trim();
    if (result.isEmpty) return null;
    return result;
  }

  static String _sourceValue(dynamic value) {
    final result = value?.toString();
    if (result != null && sourceValues.contains(result)) {
      return result;
    }
    return sourceManual;
  }

  static double _doubleValue(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  static int _intValue(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  static DateTime _dateValue(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }

  // ==========================================================================
  // DEBUG / LOGGING
  // ==========================================================================

  @override
  String toString() {
    return 'SaleCustomer('
        'id: $id, '
        'name: $name, '
        'mobileNumber: $mobileNumber, '
        'source: $source, '
        'linkedPalaiCustomerId: $linkedPalaiCustomerId, '
        'totalPurchases: $totalPurchases'
        ')';
  }
}