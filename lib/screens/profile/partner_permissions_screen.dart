class PartnerPermissionKeys {
  PartnerPermissionKeys._();

  // ---------------------------------------------------------------------------
  // Palai
  // ---------------------------------------------------------------------------

  static const String palaiView = 'palai.view';
  static const String palaiCreate = 'palai.create';
  static const String palaiUpdate = 'palai.update';
  static const String palaiDelete = 'palai.delete';

  // ---------------------------------------------------------------------------
  // Customers
  // ---------------------------------------------------------------------------

  static const String customersView = 'customers.view';
  static const String customersCreate = 'customers.create';
  static const String customersUpdate = 'customers.update';
  static const String customersDelete = 'customers.delete';

  // ---------------------------------------------------------------------------
  // Stock
  // ---------------------------------------------------------------------------

  static const String stockView = 'stock.view';
  static const String stockCreate = 'stock.create';
  static const String stockUpdate = 'stock.update';
  static const String stockDelete = 'stock.delete';

  // ---------------------------------------------------------------------------
  // Reports
  // ---------------------------------------------------------------------------

  static const String reportsView = 'reports.view';

  // ---------------------------------------------------------------------------
  // Profile
  // ---------------------------------------------------------------------------

  static const String profileView = 'profile.view';

  static const List<String> all = [
    palaiView,
    palaiCreate,
    palaiUpdate,
    palaiDelete,

    customersView,
    customersCreate,
    customersUpdate,
    customersDelete,

    stockView,
    stockCreate,
    stockUpdate,
    stockDelete,

    reportsView,
    profileView,
  ];

  static Map<String, bool> empty() {
    return {
      for (final permission in all) permission: false,
    };
  }

  static Map<String, bool> full() {
    return {
      for (final permission in all) permission: true,
    };
  }
}