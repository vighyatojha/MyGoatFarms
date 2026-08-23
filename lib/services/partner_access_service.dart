import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/partner_model.dart';

class PartnerAccessService {
  PartnerAccessService._();

  static final PartnerAccessService instance =
  PartnerAccessService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  PartnerModel? _partner;

  PartnerModel? get partner => _partner;

  bool get isPartner => _partner != null;

  bool get isActive => _partner?.isActive == true;

  PartnerPermissions get permissions =>
      _partner?.permissions ?? PartnerPermissions.none();

  Future<PartnerModel?> loadForCurrentUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      _partner = null;
      return null;
    }

    final result = await _db
        .collectionGroup('partners')
        .where('authUid', isEqualTo: uid)
        .limit(1)
        .get();

    if (result.docs.isEmpty) {
      _partner = null;
      return null;
    }

    _partner = PartnerModel.fromDoc(result.docs.first);

    return _partner;
  }

  bool can(String permission) {
    if (!isActive) return false;

    switch (permission) {
      case 'palai.view':
        return permissions.palaiView;

      case 'palai.create':
        return permissions.palaiCreate;

      case 'palai.update':
        return permissions.palaiUpdate;

      case 'palai.delete':
        return permissions.palaiDelete;

      case 'customers.view':
        return permissions.customersView;

      case 'customers.create':
        return permissions.customersCreate;

      case 'customers.update':
        return permissions.customersUpdate;

      case 'customers.delete':
        return permissions.customersDelete;

      case 'stock.view':
        return permissions.stockView;

      case 'stock.create':
        return permissions.stockCreate;

      case 'stock.update':
        return permissions.stockUpdate;

      case 'stock.delete':
        return permissions.stockDelete;

      case 'reports.view':
        return permissions.reportsView;

      case 'profile.view':
        return permissions.profileView;

      default:
        return false;
    }
  }

  void clear() {
    _partner = null;
  }
}