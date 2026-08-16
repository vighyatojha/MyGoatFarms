import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:animate_do/animate_do.dart';

import '../../app_theme.dart';
import '../../l10n/app_strings.dart';
import '../../models/bill_settings_model.dart';
import '../../models/farm_model.dart';
import '../../models/partner_model.dart';
import '../../services/firestore_service.dart';
import '../../services/image_service.dart';
import '../../services/locale_provider.dart';
import '../../services/partner_auth_service.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/fast_route.dart';
import '../login_screen.dart';
import '../palai/palai_screen.dart';
import '../stocks/stock_screen.dart';
import 'bill_settings_screen.dart';

/// Profile screen — the home of everything needed to get a farm profile
/// to 100%: farm photo, address, partners, and the app-language toggle.
///
/// Designed for owners who aren't very comfortable with apps: every field
/// is visible on one scrolling page (no hidden menus), labels are plain
/// language, and every action gives clear, immediate feedback.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _farmNameController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _addressController = TextEditingController();

  FarmModel? _farm;
  String? _farmId;
  List<PartnerModel> _partners = [];
  bool _loading = true;
  bool _savingDetails = false;
  bool _uploadingPhoto = false;
  bool _controllersInitialized = false;

  StreamSubscription<FarmModel?>? _farmSub;
  StreamSubscription<List<PartnerModel>>? _partnerSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final farm = await FirestoreService.instance.getFarmByAuthUid(uid);
    if (farm == null || !mounted) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    _farmId = farm.id;

    _farmSub = FirestoreService.instance.farmDocStream(farm.id).listen((f) {
      if (f == null || !mounted) return;
      setState(() {
        _farm = f;
        _loading = false;
        if (!_controllersInitialized) {
          _farmNameController.text = f.farmName;
          _ownerNameController.text = f.ownerName;
          _addressController.text = f.address;
          _controllersInitialized = true;
        }
      });
      // A language chosen on another device should show up here too,
      // without fighting a choice just made locally.
      if (mounted) context.read<LocaleProvider>().syncFromFarm(f.preferredLanguage);
    });

    _partnerSub = FirestoreService.instance.partnersStream(farm.id).listen((partners) {
      if (!mounted) return;
      setState(() => _partners = partners);
    });
  }

  @override
  void dispose() {
    _farmNameController.dispose();
    _ownerNameController.dispose();
    _addressController.dispose();
    _farmSub?.cancel();
    _partnerSub?.cancel();
    super.dispose();
  }

  int get _percent => _farm?.completionPercent(partnerCount: _partners.length) ?? 0;

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? AppColors.error : AppColors.darkGreen),
    );
  }

  Future<void> _saveDetails() async {
    if (_farmId == null) return;
    setState(() => _savingDetails = true);
    try {
      await FirestoreService.instance.updateFarmBasics(
        _farmId!,
        farmName: _farmNameController.text,
        ownerName: _ownerNameController.text,
        address: _addressController.text,
      );
      _showSnack(AppStrings.t(context, 'profile_updated'));
    } catch (e) {
      _showSnack(FirestoreService.instance.describeError(e), isError: true);
    } finally {
      if (mounted) setState(() => _savingDetails = false);
    }
  }

  Future<void> _pickPhoto() async {
    if (_farmId == null) return;
    try {
      final picked = await ImageService.instance.pickFromGallery();
      if (picked == null) return; // user cancelled the picker
      setState(() => _uploadingPhoto = true);
      await FirestoreService.instance.updateProfileImage(_farmId!, picked.bytes, picked.contentType);
      _showSnack(AppStrings.t(context, 'photo_updated'));
    } on ImageTooLargeException catch (e) {
      _showSnack(e.message, isError: true);
    } catch (e) {
      _showSnack('Could not update photo. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _removePhoto() async {
    if (_farmId == null) return;
    try {
      await FirestoreService.instance.removeProfileImage(_farmId!);
    } catch (e) {
      _showSnack(FirestoreService.instance.describeError(e), isError: true);
    }
  }

  void _showPhotoOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: AppColors.primaryGreen),
                title: Text(
                  AppStrings.t(context, 'change_photo'),
                  style: AppTheme.body(size: 15, color: AppColors.textDark, weight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickPhoto();
                },
              ),
              if (_farm?.profileImage != null)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: AppColors.error),
                  title: Text(
                    AppStrings.t(context, 'remove_photo'),
                    style: AppTheme.body(size: 15, color: AppColors.error, weight: FontWeight.w600),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _removePhoto();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAddPartnerSheet() async {
    if (_farmId == null) return;
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _AddPartnerSheet(farmId: _farmId!),
    );
    if (added == true) _showSnack('Partner added');
  }

  Future<void> _confirmRemovePartner(PartnerModel partner) async {
    if (_farmId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(AppStrings.t(context, 'remove_partner_q'), style: AppTheme.heading(size: 16)),
        content: Text(partner.name, style: AppTheme.body(size: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(AppStrings.t(context, 'cancel'), style: AppTheme.body(size: 14, weight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              AppStrings.t(context, 'remove'),
              style: AppTheme.body(size: 14, color: AppColors.error, weight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await FirestoreService.instance.deletePartner(_farmId!, partner.id);
      } catch (e) {
        _showSnack(FirestoreService.instance.describeError(e), isError: true);
      }
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
    );
  }

  /// Profile was opened with Navigator.push (it's a full page, not an
  /// IndexedStack tab), so switching to another tab from here means
  /// popping back to the shell first, then — for Palai/Stock — pushing
  /// that screen the same way the rest of the app already does.
  void _onBottomNavTap(int index) {
    switch (index) {
      case 4: // Profile — already here.
        break;
      case 3:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reports coming soon'), backgroundColor: AppColors.darkGreen),
        );
        break;
      case 0:
        Navigator.of(context).pop();
        break;
      case 1:
        Navigator.of(context).pop();
        Navigator.of(context).push(fastRoute(const PalaiScreen()));
        break;
      case 2:
        Navigator.of(context).pop();
        Navigator.of(context).push(fastRoute(const StockScreen()));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.paleGreen,
        bottomNavigationBar: AppBottomNav(currentIndex: 4, onTap: _onBottomNavTap),
        body: const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
      );
    }

    final farm = _farm;
    final farmName = farm?.farmName.isNotEmpty == true ? farm!.farmName : 'My Goat Farms';
    final ownerName = farm?.ownerName ?? '';

    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      bottomNavigationBar: AppBottomNav(currentIndex: 4, onTap: _onBottomNavTap),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FadeInDown(
                duration: const Duration(milliseconds: 220),
                child: _buildHeader(farmName, ownerName),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FadeInUp(
                      delay: const Duration(milliseconds: 40),
                      duration: const Duration(milliseconds: 200),
                      child: _buildCompletionCard(),
                    ),
                    const SizedBox(height: 20),
                    FadeInUp(
                      delay: const Duration(milliseconds: 70),
                      duration: const Duration(milliseconds: 200),
                      child: _buildYourDetailsCard(farm),
                    ),
                    const SizedBox(height: 20),
                    FadeInUp(
                      delay: const Duration(milliseconds: 100),
                      duration: const Duration(milliseconds: 200),
                      child: _buildCompleteProfileSection(farm),
                    ),
                    const SizedBox(height: 20),
                    FadeInUp(
                      delay: const Duration(milliseconds: 115),
                      duration: const Duration(milliseconds: 200),
                      child: _buildBillDetailsCard(farm),
                    ),
                    const SizedBox(height: 28),
                    FadeInUp(
                      delay: const Duration(milliseconds: 130),
                      duration: const Duration(milliseconds: 200),
                      child: _buildLogoutButton(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // Header
  // -------------------------------------------------------------------

  Widget _buildHeader(String farmName, String ownerName) {
    return Container(
      padding: const EdgeInsets.only(top: 8, bottom: 28, left: 20, right: 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: AppColors.headerGradient,
        ),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(32), bottomRight: Radius.circular(32)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
              Expanded(
                child: Text(
                  AppStrings.t(context, 'profile_title'),
                  textAlign: TextAlign.center,
                  style: AppTheme.heading(size: 17, color: Colors.white),
                ),
              ),
              const SizedBox(width: 48), // balances the back button
            ],
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _showPhotoOptions,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: ClipOval(
                    child: _farm?.profileImage != null
                        ? Image.memory(_farm!.profileImage!, fit: BoxFit.cover, width: 96, height: 96)
                        : const Icon(Icons.pets, color: AppColors.primaryGreen, size: 42),
                  ),
                ),
                if (_uploadingPhoto)
                  Container(
                    width: 96,
                    height: 96,
                    decoration: const BoxDecoration(color: Colors.black26, shape: BoxShape.circle),
                    child: const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.darkGreen,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.camera_alt, color: Colors.white, size: 15),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(farmName, style: AppTheme.heading(size: 18, color: Colors.white), textAlign: TextAlign.center),
          if (ownerName.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(ownerName, style: AppTheme.body(size: 13, color: Colors.white.withOpacity(0.9))),
          ],
          const SizedBox(height: 6),
          Text(
            AppStrings.t(context, 'tap_to_change_photo'),
            style: AppTheme.body(size: 11, color: Colors.white.withOpacity(0.75)),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // Completion card
  // -------------------------------------------------------------------

  Widget _buildCompletionCard() {
    final percent = _percent;
    final isComplete = percent >= 100;
    return Container(
      decoration: AppTheme.card(radius: 18),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: percent / 100,
                  strokeWidth: 6,
                  backgroundColor: AppColors.lightGreen,
                  color: isComplete ? AppColors.success : AppColors.primaryGreen,
                ),
                Text('$percent%', style: AppTheme.heading(size: 13, color: AppColors.darkGreen)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isComplete ? '🎉 100% ${AppStrings.t(context, 'profile_complete')}' : '$percent% ${AppStrings.t(context, 'profile_complete')}',
                  style: AppTheme.heading(size: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  isComplete
                      ? 'Nice work — everything is set up.'
                      : 'Finish the items below to reach 100%.',
                  style: AppTheme.body(size: 12),
                ),
              ],
            ),
          ),
          if (isComplete) const Icon(Icons.check_circle, color: AppColors.success, size: 28),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // Your Details
  // -------------------------------------------------------------------

  Widget _buildYourDetailsCard(FarmModel? farm) {
    return Container(
      decoration: AppTheme.card(radius: 18),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppStrings.t(context, 'your_details'), style: AppTheme.heading(size: 15, color: AppColors.darkGreen)),
          const SizedBox(height: 14),
          TextField(
            controller: _farmNameController,
            decoration: InputDecoration(
              labelText: AppStrings.t(context, 'farm_name'),
              prefixIcon: const Icon(Icons.storefront_outlined, color: AppColors.primaryGreen),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ownerNameController,
            decoration: InputDecoration(
              labelText: AppStrings.t(context, 'owner_name'),
              prefixIcon: const Icon(Icons.person_outline, color: AppColors.primaryGreen),
            ),
          ),
          const SizedBox(height: 12),
          _buildLockedField(
            label: AppStrings.t(context, 'mobile_number'),
            value: farm?.mobileNumber ?? '',
            icon: Icons.phone_outlined,
          ),
          const SizedBox(height: 12),
          _buildLockedField(
            label: AppStrings.t(context, 'email'),
            value: farm?.email ?? '',
            icon: Icons.email_outlined,
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              AppStrings.t(context, 'login_locked_note'),
              style: AppTheme.body(size: 11, color: AppColors.textGrey),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _savingDetails ? null : _saveDetails,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: _savingDetails
                  ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
              )
                  : Text(AppStrings.t(context, 'save_changes'), style: AppTheme.heading(size: 14, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLockedField({required String label, required String value, required IconData icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(color: const Color(0xFFF1F3F1), borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textGrey, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTheme.body(size: 11, color: AppColors.textGrey)),
                Text(value.isEmpty ? '—' : value, style: AppTheme.body(size: 14, color: AppColors.textDark, weight: FontWeight.w600)),
              ],
            ),
          ),
          const Icon(Icons.lock_outline, color: AppColors.textGrey, size: 16),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // Complete Your Profile section (address, partners, language)
  // -------------------------------------------------------------------

  Widget _buildCompleteProfileSection(FarmModel? farm) {
    final hasAddress = (farm?.address ?? '').trim().isNotEmpty;
    return Container(
      decoration: AppTheme.card(radius: 18),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.t(context, 'complete_your_profile'),
            style: AppTheme.heading(size: 15, color: AppColors.darkGreen),
          ),
          const SizedBox(height: 16),

          // Farm address
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _statusIcon(hasAddress),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _addressController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: AppStrings.t(context, 'farm_address'),
                    prefixIcon: const Icon(Icons.location_on_outlined, color: AppColors.primaryGreen),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 18),

          // Partners
          Row(
            children: [
              _statusIcon(_partners.isNotEmpty),
              const SizedBox(width: 10),
              Expanded(
                child: Text(AppStrings.t(context, 'partners'), style: AppTheme.heading(size: 14)),
              ),
              TextButton(
                onPressed: _showAddPartnerSheet,
                child: Text(
                  AppStrings.t(context, 'add_partner'),
                  style: AppTheme.body(size: 13, color: AppColors.darkGreen, weight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (_partners.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 4),
              child: Text(AppStrings.t(context, 'no_partners_yet'), style: AppTheme.body(size: 12)),
            )
          else
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 6),
              child: Column(children: _partners.map(_buildPartnerTile).toList()),
            ),
          const SizedBox(height: 8),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 18),

          // Language toggle — lives only here, in the Complete Profile section.
          Text(AppStrings.t(context, 'language'), style: AppTheme.heading(size: 14)),
          const SizedBox(height: 10),
          _buildLanguageToggle(),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // Bill Details — what gets printed on the Palai check-out bill
  // -------------------------------------------------------------------

  Widget _buildBillDetailsCard(FarmModel? farm) {
    final settings = farm?.billSettings ?? const BillSettings();
    return Container(
      decoration: AppTheme.card(radius: 18),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_outlined, color: AppColors.primaryGreen),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Bill Details', style: AppTheme.heading(size: 15, color: AppColors.darkGreen)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Customize what shows on the Palai check-out bill — business name, address, phone, UPI payment info, thank-you note and terms.',
            style: AppTheme.body(size: 12),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFF1F3F1), borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(settings.businessName, style: AppTheme.body(size: 13, color: AppColors.textDark, weight: FontWeight.w700)),
                if (settings.address.trim().isNotEmpty) Text(settings.address, style: AppTheme.body(size: 11)),
                if (settings.phone.trim().isNotEmpty) Text('Phone: ${settings.phone}', style: AppTheme.body(size: 11)),
                if (settings.upiId.trim().isNotEmpty) Text('UPI: ${settings.upiId}', style: AppTheme.body(size: 11)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _farmId == null
                  ? null
                  : () => Navigator.of(context).push(
                        fastRoute(BillSettingsScreen(farmId: _farmId!, initialSettings: settings)),
                      ),
              icon: const Icon(Icons.edit_outlined, color: AppColors.primaryGreen),
              label: Text('Edit Bill Details', style: AppTheme.heading(size: 13, color: AppColors.primaryGreen)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.primaryGreen),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusIcon(bool done) {
    return Container(
      width: 22,
      height: 22,
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? AppColors.success.withOpacity(0.15) : AppColors.warning.withOpacity(0.15),
      ),
      child: Icon(
        done ? Icons.check : Icons.priority_high,
        size: 14,
        color: done ? AppColors.success : AppColors.warning,
      ),
    );
  }

  Widget _buildPartnerTile(PartnerModel partner) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          const CircleAvatar(radius: 16, backgroundColor: AppColors.lightGreen, child: Icon(Icons.person, color: AppColors.primaryGreen, size: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(partner.name, style: AppTheme.body(size: 13, color: AppColors.textDark, weight: FontWeight.w600)),
                Text(partner.mobileNumber, style: AppTheme.body(size: 11)),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _confirmRemovePartner(partner),
            icon: const Icon(Icons.close, size: 18, color: AppColors.textGrey),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageToggle() {
    final current = context.watch<LocaleProvider>().language;
    return Row(
      children: AppLanguage.values.map((lang) {
        final selected = lang == current;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () async {
                await context.read<LocaleProvider>().setLanguage(lang);
                if (_farmId != null) {
                  FirestoreService.instance.updatePreferredLanguage(_farmId!, lang.code);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primaryGreen : const Color(0xFFF1F3F1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: selected ? AppColors.primaryGreen : Colors.transparent, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    lang.label,
                    style: AppTheme.heading(size: 13, color: selected ? Colors.white : AppColors.textDark),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildLogoutButton() {
    return SizedBox(
      height: 52,
      child: OutlinedButton.icon(
        onPressed: _logout,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.error),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        ),
        icon: const Icon(Icons.logout, color: AppColors.error),
        label: Text(AppStrings.t(context, 'logout'), style: AppTheme.heading(size: 14, color: AppColors.error)),
      ),
    );
  }
}

/// Bottom sheet form for "+ Add Partner": Name, Mobile, Email, Password.
///
/// Creates the partner a real login (via [PartnerAuthService], on an
/// isolated secondary Firebase app so the farm owner's own session is
/// never disturbed) and then stores their name/mobile/email in Firestore.
/// The password itself is never written to Firestore.
class _AddPartnerSheet extends StatefulWidget {
  final String farmId;
  const _AddPartnerSheet({required this.farmId});

  @override
  State<_AddPartnerSheet> createState() => _AddPartnerSheetState();
}

class _AddPartnerSheetState extends State<_AddPartnerSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final uid = await PartnerAuthService.instance.createPartnerAccount(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      await FirestoreService.instance.addPartner(
        widget.farmId,
        name: _nameController.text.trim(),
        mobileNumber: _mobileController.text.trim(),
        email: _emailController.text.trim(),
        authUid: uid,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on FirebaseAuthException catch (e) {
      _showError(_mapAuthError(e.code));
    } catch (_) {
      _showError('Could not add partner. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _mapAuthError(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'This email is already used by another account';
      case 'invalid-email':
        return 'Enter a valid email address';
      case 'weak-password':
        return 'Password is too weak (minimum 6 characters)';
      default:
        return 'Could not add partner. Please try again.';
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(height: 16),
                Text(AppStrings.t(context, 'add_partner'), style: AppTheme.heading(size: 17)),
                const SizedBox(height: 4),
                Text('They will get their own login to help manage the farm.', style: AppTheme.body(size: 12)),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    hintText: AppStrings.t(context, 'partner_name'),
                    prefixIcon: const Icon(Icons.person_outline, color: AppColors.primaryGreen),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter partner name' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _mobileController,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  decoration: InputDecoration(
                    hintText: AppStrings.t(context, 'partner_mobile'),
                    prefixIcon: const Icon(Icons.phone_outlined, color: AppColors.primaryGreen),
                    counterText: '',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Enter mobile number';
                    if (!RegExp(r'^[0-9]{10}$').hasMatch(v.trim())) return 'Enter a valid 10-digit number';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: AppStrings.t(context, 'partner_email'),
                    prefixIcon: const Icon(Icons.email_outlined, color: AppColors.primaryGreen),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Enter email address';
                    final emailRegex = RegExp(r'^[\w\.\-]+@[\w\-]+\.[\w\-\.]+$');
                    if (!emailRegex.hasMatch(v.trim())) return 'Enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    hintText: AppStrings.t(context, 'partner_password'),
                    prefixIcon: const Icon(Icons.lock_outline, color: AppColors.primaryGreen),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: AppColors.textGrey),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) => (v == null || v.length < 6) ? 'Minimum 6 characters' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirmController,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    hintText: AppStrings.t(context, 'confirm_password'),
                    prefixIcon: const Icon(Icons.lock_outline, color: AppColors.primaryGreen),
                  ),
                  validator: (v) => (v != _passwordController.text) ? 'Passwords do not match' : null,
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : () => Navigator.pop(context, false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                        child: Text(AppStrings.t(context, 'cancel'), style: AppTheme.heading(size: 14, color: AppColors.textGrey)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _saving ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryGreen,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                        child: _saving
                            ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                        )
                            : Text(AppStrings.t(context, 'add'), style: AppTheme.heading(size: 14, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
