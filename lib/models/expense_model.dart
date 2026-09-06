import 'package:cloud_firestore/cloud_firestore.dart';

/// A single farm-wide expense record, stored at
/// `farms/{farmId}/expenses/{id}`.
///
/// This is intentionally separate from [OwnFarmExpense]
/// (models/own_farm_models.dart), which is a per-goat expense log scoped
/// to the "Own Farm" module. Merging the two would require migrating
/// existing Own Farm data and touching an unrelated, already-working
/// module — out of scope for this integration. If Own Farm expenses
/// should ever roll into the Finance totals, that is a deliberate
/// follow-up, not an automatic side effect of this model.
class ExpenseModel {
  final String id;

  final String title;
  final String category;
  final double amount;

  final double? quantity;
  final double? unitPrice;
  final String? unit;

  final String? supplierName;
  final String paymentMethod;
  final String? invoiceNumber;
  final String note;

  final DateTime date;
  final DateTime createdAt;
  final DateTime updatedAt;

  final String? createdBy;
  final String? createdByName;
  final String? createdByRole;

  /// 'active' or 'voided'. Voided expenses are excluded from every
  /// financial calculation but kept for auditability (spec Rule 7) —
  /// never hard-deleted.
  final String status;

  /// Optional link back to the record that caused this expense — e.g.
  /// a stock movement — so the same real-world purchase never produces
  /// two expenses (spec Rule 5 / §43).
  final String? referenceType;
  final String? referenceId;

  const ExpenseModel({
    required this.id,
    required this.title,
    required this.category,
    required this.amount,
    this.quantity,
    this.unitPrice,
    this.unit,
    this.supplierName,
    required this.paymentMethod,
    this.invoiceNumber,
    this.note = '',
    required this.date,
    required this.createdAt,
    required this.updatedAt,
    this.createdBy,
    this.createdByName,
    this.createdByRole,
    this.status = 'active',
    this.referenceType,
    this.referenceId,
  });

  bool get isVoided => status == 'voided';

  factory ExpenseModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return ExpenseModel(
      id: doc.id,
      title: (data['title'] ?? '').toString(),
      category: (data['category'] ?? 'Other').toString(),
      amount: (data['amount'] ?? 0).toDouble(),
      quantity: (data['quantity'] as num?)?.toDouble(),
      unitPrice: (data['unitPrice'] as num?)?.toDouble(),
      unit: data['unit'] as String?,
      supplierName: data['supplierName'] as String?,
      paymentMethod: (data['paymentMethod'] ?? '').toString(),
      invoiceNumber: data['invoiceNumber'] as String?,
      note: (data['note'] ?? '').toString(),
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdBy: data['createdBy'] as String?,
      createdByName: data['createdByName'] as String?,
      createdByRole: data['createdByRole'] as String?,
      status: (data['status'] ?? 'active').toString(),
      referenceType: data['referenceType'] as String?,
      referenceId: data['referenceId'] as String?,
    );
  }

  Map<String, dynamic> toCreateMap({
    required String createdBy,
    required String createdByName,
    required String createdByRole,
  }) {
    return {
      'title': title.trim(),
      'category': category,
      'amount': amount,
      if (quantity != null) 'quantity': quantity,
      if (unitPrice != null) 'unitPrice': unitPrice,
      if (unit != null && unit!.trim().isNotEmpty) 'unit': unit!.trim(),
      if (supplierName != null && supplierName!.trim().isNotEmpty)
        'supplierName': supplierName!.trim(),
      'paymentMethod': paymentMethod,
      if (invoiceNumber != null && invoiceNumber!.trim().isNotEmpty)
        'invoiceNumber': invoiceNumber!.trim(),
      'note': note.trim(),
      'date': Timestamp.fromDate(date),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdBy': createdBy,
      'createdByName': createdByName,
      'createdByRole': createdByRole,
      'status': 'active',
      if (referenceType != null) 'referenceType': referenceType,
      if (referenceId != null) 'referenceId': referenceId,
    };
  }

  Map<String, dynamic> toUpdateMap() {
    return {
      'title': title.trim(),
      'category': category,
      'amount': amount,
      if (quantity != null) 'quantity': quantity,
      if (unitPrice != null) 'unitPrice': unitPrice,
      if (unit != null && unit!.trim().isNotEmpty) 'unit': unit!.trim(),
      'supplierName': supplierName?.trim(),
      'paymentMethod': paymentMethod,
      'invoiceNumber': invoiceNumber?.trim(),
      'note': note.trim(),
      'date': Timestamp.fromDate(date),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
