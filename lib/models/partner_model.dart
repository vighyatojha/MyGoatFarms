import 'package:cloud_firestore/cloud_firestore.dart';

class PartnerPermissions {
  final bool palaiView;
  final bool palaiCreate;
  final bool palaiUpdate;
  final bool palaiDelete;

  final bool customersView;
  final bool customersCreate;
  final bool customersUpdate;
  final bool customersDelete;

  final bool stockView;
  final bool stockCreate;
  final bool stockUpdate;
  final bool stockDelete;

  final bool reportsView;
  final bool profileView;

  // --- Finance ---
  final bool financeView;
  final bool financeExpenseCreate;
  final bool financeExpenseEdit;
  final bool financeExpenseVoid;
  final bool financeRevenueCreate;
  final bool financeRevenueEdit;
  final bool financeRevenueVoid;
  final bool financeLedgerView;
  final bool financeReportsView;

  const PartnerPermissions({
    this.palaiView = false,
    this.palaiCreate = false,
    this.palaiUpdate = false,
    this.palaiDelete = false,
    this.customersView = false,
    this.customersCreate = false,
    this.customersUpdate = false,
    this.customersDelete = false,
    this.stockView = false,
    this.stockCreate = false,
    this.stockUpdate = false,
    this.stockDelete = false,
    this.reportsView = false,
    this.profileView = false,
    this.financeView = false,
    this.financeExpenseCreate = false,
    this.financeExpenseEdit = false,
    this.financeExpenseVoid = false,
    this.financeRevenueCreate = false,
    this.financeRevenueEdit = false,
    this.financeRevenueVoid = false,
    this.financeLedgerView = false,
    this.financeReportsView = false,
  });

  factory PartnerPermissions.fromMap(
      Map<String, dynamic>? map,
      ) {
    final data = map ?? {};

    return PartnerPermissions(
      palaiView: data['palaiView'] == true,
      palaiCreate: data['palaiCreate'] == true,
      palaiUpdate: data['palaiUpdate'] == true,
      palaiDelete: data['palaiDelete'] == true,

      customersView: data['customersView'] == true,
      customersCreate: data['customersCreate'] == true,
      customersUpdate: data['customersUpdate'] == true,
      customersDelete: data['customersDelete'] == true,

      stockView: data['stockView'] == true,
      stockCreate: data['stockCreate'] == true,
      stockUpdate: data['stockUpdate'] == true,
      stockDelete: data['stockDelete'] == true,

      reportsView: data['reportsView'] == true,
      profileView: data['profileView'] == true,

      financeView: data['financeView'] == true,
      financeExpenseCreate: data['financeExpenseCreate'] == true,
      financeExpenseEdit: data['financeExpenseEdit'] == true,
      financeExpenseVoid: data['financeExpenseVoid'] == true,
      financeRevenueCreate: data['financeRevenueCreate'] == true,
      financeRevenueEdit: data['financeRevenueEdit'] == true,
      financeRevenueVoid: data['financeRevenueVoid'] == true,
      financeLedgerView: data['financeLedgerView'] == true,
      financeReportsView: data['financeReportsView'] == true,
    );
  }

  factory PartnerPermissions.none() {
    return const PartnerPermissions();
  }

  Map<String, dynamic> toMap() {
    return {
      'palaiView': palaiView,
      'palaiCreate': palaiCreate,
      'palaiUpdate': palaiUpdate,
      'palaiDelete': palaiDelete,

      'customersView': customersView,
      'customersCreate': customersCreate,
      'customersUpdate': customersUpdate,
      'customersDelete': customersDelete,

      'stockView': stockView,
      'stockCreate': stockCreate,
      'stockUpdate': stockUpdate,
      'stockDelete': stockDelete,

      'reportsView': reportsView,
      'profileView': profileView,

      'financeView': financeView,
      'financeExpenseCreate': financeExpenseCreate,
      'financeExpenseEdit': financeExpenseEdit,
      'financeExpenseVoid': financeExpenseVoid,
      'financeRevenueCreate': financeRevenueCreate,
      'financeRevenueEdit': financeRevenueEdit,
      'financeRevenueVoid': financeRevenueVoid,
      'financeLedgerView': financeLedgerView,
      'financeReportsView': financeReportsView,
    };
  }
}

class PartnerModel {
  final String id;
  final String name;
  final String mobileNumber;
  final String email;
  final String authUid;
  final DateTime? createdAt;
  final bool isActive;
  final PartnerPermissions permissions;

  /// The id of the farm this partner belongs to — i.e. the id of the
  /// `farms/{farmId}` document that owns the `partners` subcollection
  /// this record lives in. Not stored in Firestore itself; derived from
  /// [doc]'s path in [fromDoc] so callers (e.g. resolving which farm a
  /// partner should land on after login) don't need a second lookup.
  final String farmId;

  PartnerModel({
    required this.id,
    required this.name,
    required this.mobileNumber,
    required this.email,
    required this.authUid,
    required this.farmId,
    this.createdAt,
    this.isActive = true,
    this.permissions = const PartnerPermissions(),
  });

  factory PartnerModel.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};

    return PartnerModel(
      id: doc.id,
      name: data['name'] ?? '',
      mobileNumber: data['mobileNumber'] ?? '',
      email: data['email'] ?? '',
      authUid: data['authUid'] ?? doc.id,
      // doc.reference is farms/{farmId}/partners/{partnerId}, so the
      // grandparent (parent.parent) is the farms/{farmId} document.
      farmId: doc.reference.parent.parent?.id ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      isActive: data['isActive'] != false,
      permissions: PartnerPermissions.fromMap(
        data['permissions'] as Map<String, dynamic>?,
      ),
    );
  }
}
