/// The admin's name and contact details, shown to a farm owner while their
/// registration is awaiting approval (see [FarmApprovalPendingScreen]).
///
/// Backed by the single Firestore document `config/adminContact` so the
/// admin panel can update these details without an app release. If that
/// document hasn't been created yet, [AdminContact.fallback] is used instead
/// so the waiting screen never shows blank contact fields.
class AdminContact {
  final String name;
  final String phone;
  final String email;

  const AdminContact({
    required this.name,
    required this.phone,
    required this.email,
  });

  /// Shown until an admin fills in `config/adminContact` in Firestore, or if
  /// that read fails for any reason (offline, permissions, etc).
  static const AdminContact fallback = AdminContact(
    name: 'My Goat Farms Support',
    phone: '',
    email: 'mygoatfarm20@gmail.com',
  );

  factory AdminContact.fromMap(Map<String, dynamic>? data) {
    if (data == null) return fallback;

    final name = (data['name'] as String?)?.trim();
    final phone = (data['phone'] as String?)?.trim();
    final email = (data['email'] as String?)?.trim();

    return AdminContact(
      name: (name == null || name.isEmpty) ? fallback.name : name,
      phone: phone ?? fallback.phone,
      email: (email == null || email.isEmpty) ? fallback.email : email,
    );
  }
}