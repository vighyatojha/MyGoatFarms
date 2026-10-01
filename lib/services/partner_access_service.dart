import 'package:firebase_auth/firebase_auth.dart';

import '../models/partner_model.dart';
import 'firestore_service.dart';

class PartnerAccessService {
  PartnerAccessService._();

  static final PartnerAccessService instance =
  PartnerAccessService._();

  PartnerModel? _partner;

  PartnerModel? get partner => _partner;

  bool get isPartner => _partner != null;

  bool get isActive => _partner?.isActive == true;

  PartnerPermissions get permissions =>
      _partner?.permissions ?? PartnerPermissions.none();

  /// Delegates to [FirestoreService.getPartnerByAuthUid], which wraps the
  /// query in a timeout + try/catch. Previously this ran the
  /// `collectionGroup('partners')` query directly with no timeout, so a
  /// missing Firestore index/rule for the query could leave any caller
  /// awaiting this `Future` forever instead of failing gracefully.
  Future<PartnerModel?> loadForCurrentUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      _partner = null;
      return null;
    }

    _partner = await FirestoreService.instance.getPartnerByAuthUid(uid);
    return _partner;
  }

  /// True when [permission] should be allowed for whoever is signed in
  /// right now.
  ///
  /// The farm OWNER (not a partner at all — [isPartner] false) always has
  /// full access; permissions only ever restrict an invited PARTNER. No
  /// screen in the app called [can] directly before this — this is the
  /// first place that distinction is made explicit, so double-check it
  /// against how partner accounts actually sign in before relying on it
  /// elsewhere.
  bool allows(String permission) {
    if (!isPartner) return true;
    return can(permission);
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

      case 'finance.view':
        return permissions.financeView;

      case 'finance.expenseCreate':
        return permissions.financeExpenseCreate;

      case 'finance.expenseEdit':
        return permissions.financeExpenseEdit;

      case 'finance.expenseVoid':
        return permissions.financeExpenseVoid;

      case 'finance.revenueCreate':
        return permissions.financeRevenueCreate;

      case 'finance.revenueEdit':
        return permissions.financeRevenueEdit;

      case 'finance.revenueVoid':
        return permissions.financeRevenueVoid;

      case 'finance.ledgerView':
        return permissions.financeLedgerView;

      case 'finance.reportsView':
        return permissions.financeReportsView;

      case 'trading.view':
        return permissions.tradingView;

      case 'trading.purchaseCreate':
        return permissions.tradingPurchaseCreate;

      case 'trading.sell':
        return permissions.tradingSell;

      case 'trading.supplierPayment':
        return permissions.tradingSupplierPayment;

      case 'trading.receive':
        return permissions.tradingReceive;

      case 'trading.manageStock':
        return permissions.tradingManageStock;

      default:
        return false;
    }
  }

  void clear() {
    _partner = null;
  }
}