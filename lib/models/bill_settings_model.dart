/// Farm-level settings that control what appears on the printed/shared
/// Palai check-out bill: business name, tagline, address, phone, UPI/
/// payment info, a thank-you footer note, and optional terms &
/// conditions. Editable from Profile > Bill Details.
class BillSettings {
  final String businessName;
  final String tagline;
  final String address;
  final String phone;
  final String upiId;
  final String footerNote;
  final String terms;

  const BillSettings({
    this.businessName = 'My Goat Farms',
    this.tagline = 'Palai - Goat Boarding & Care',
    this.address = '',
    this.phone = '',
    this.upiId = '',
    this.footerNote = 'Thank you for trusting us with your goat.',
    this.terms = '',
  });

  /// Builds settings from the farm document's `billSettings` map. Falls
  /// back to the farm's own name/address/mobile number when a field has
  /// never been set, so a farm that hasn't visited the new Bill Details
  /// screen yet still gets a sensible bill instead of blank fields.
  factory BillSettings.fromMap(
    Map<String, dynamic>? data, {
    String fallbackName = 'My Goat Farms',
    String fallbackAddress = '',
    String fallbackPhone = '',
  }) {
    String pick(String? value, String fallback) =>
        (value != null && value.trim().isNotEmpty) ? value : fallback;

    return BillSettings(
      businessName: pick(data?['businessName'] as String?, fallbackName),
      tagline: pick(data?['tagline'] as String?, 'Palai - Goat Boarding & Care'),
      address: pick(data?['address'] as String?, fallbackAddress),
      phone: pick(data?['phone'] as String?, fallbackPhone),
      upiId: (data?['upiId'] as String?) ?? '',
      footerNote: pick(data?['footerNote'] as String?, 'Thank you for trusting us with your goat.'),
      terms: (data?['terms'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'businessName': businessName,
      'tagline': tagline,
      'address': address,
      'phone': phone,
      'upiId': upiId,
      'footerNote': footerNote,
      'terms': terms,
    };
  }
}
