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

  PartnerModel({
    required this.id,
    required this.name,
    required this.mobileNumber,
    required this.email,
    required this.authUid,
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
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      isActive: data['isActive'] != false,
      permissions: PartnerPermissions.fromMap(
        data['permissions'] as Map<String, dynamic>?,
      ),
    );
  }
}