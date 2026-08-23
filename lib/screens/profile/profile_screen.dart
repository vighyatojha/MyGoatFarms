import 'dart:async';

import 'package:animate_do/animate_do.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
import '../customers/customer_management_screen.dart';
import '../login_screen.dart';
import '../palai/palai_screen.dart';
import '../stocks/stock_screen.dart';
import 'partner_permissions_screen.dart';

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
  bool _loggingOut = false;

  StreamSubscription<FarmModel?>? _farmSub;
  StreamSubscription<List<PartnerModel>>? _partnerSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;

      if (uid == null) {
        if (mounted) {
          setState(() => _loading = false);
        }
        return;
      }

      final farm =
      await FirestoreService.instance.getFarmByAuthUid(uid);

      if (!mounted) return;

      if (farm == null) {
        setState(() => _loading = false);
        return;
      }

      _farmId = farm.id;

      _farmSub = FirestoreService.instance
          .farmDocStream(farm.id)
          .listen(
            (farm) {
          if (!mounted || farm == null) return;

          setState(() {
            _farm = farm;
            _loading = false;

            if (!_controllersInitialized) {
              _farmNameController.text = farm.farmName;
              _ownerNameController.text = farm.ownerName;
              _addressController.text = farm.address;

              _controllersInitialized = true;
            }
          });

          context
              .read<LocaleProvider>()
              .syncFromFarm(farm.preferredLanguage);
        },
        onError: (_) {
          if (mounted) {
            setState(() => _loading = false);
          }
        },
      );

      _partnerSub = FirestoreService.instance
          .partnersStream(farm.id)
          .listen(
            (partners) {
          if (!mounted) return;

          setState(() {
            _partners = partners;
          });
        },
      );
    } catch (e) {
      if (!mounted) return;

      setState(() => _loading = false);

      _showSnack(
        FirestoreService.instance.describeError(e),
        isError: true,
      );
    }
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

  int get _percent {
    return _farm?.completionPercent(
      partnerCount: _partners.length,
    ) ??
        0;
  }

  bool get _hasUnsavedDetails {
    final farm = _farm;

    if (farm == null) return false;

    return _farmNameController.text.trim() != farm.farmName ||
        _ownerNameController.text.trim() != farm.ownerName ||
        _addressController.text.trim() != farm.address;
  }

  void _showSnack(
      String message, {
        bool isError = false,
      }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor:
          isError ? AppColors.error : AppColors.darkGreen,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
  }

  Future<bool> _confirmLeaveIfNeeded() async {
    if (!_hasUnsavedDetails) return true;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Unsaved changes'),
          content: const Text(
            'You have changes that have not been saved. '
                'Do you want to leave without saving?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Stay'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.error,
              ),
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Leave'),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  Future<void> _saveDetails() async {
    if (_farmId == null || _savingDetails) return;

    final farmName = _farmNameController.text.trim();
    final ownerName = _ownerNameController.text.trim();
    final address = _addressController.text.trim();

    if (farmName.isEmpty) {
      _showSnack(
        'Farm name cannot be empty.',
        isError: true,
      );
      return;
    }

    if (ownerName.isEmpty) {
      _showSnack(
        'Owner name cannot be empty.',
        isError: true,
      );
      return;
    }

    setState(() {
      _savingDetails = true;
    });

    try {
      await FirestoreService.instance.updateFarmBasics(
        _farmId!,
        farmName: farmName,
        ownerName: ownerName,
        address: address,
      );

      _showSnack(
        AppStrings.t(context, 'profile_updated'),
      );
    } catch (e) {
      _showSnack(
        FirestoreService.instance.describeError(e),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _savingDetails = false;
        });
      }
    }
  }

  Future<void> _pickPhoto() async {
    if (_farmId == null || _uploadingPhoto) return;

    try {
      final picked =
      await ImageService.instance.pickFromGallery();

      if (picked == null) return;

      if (mounted) {
        setState(() {
          _uploadingPhoto = true;
        });
      }

      await FirestoreService.instance.updateProfileImage(
        _farmId!,
        picked.bytes,
        picked.contentType,
      );

      _showSnack(
        AppStrings.t(context, 'photo_updated'),
      );
    } on ImageTooLargeException catch (e) {
      _showSnack(
        e.message,
        isError: true,
      );
    } catch (e) {
      _showSnack(
        'Could not update photo. Please try again.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _uploadingPhoto = false;
        });
      }
    }
  }

  Future<void> _removePhoto() async {
    if (_farmId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Remove farm photo?'),
          content: const Text(
            'The current farm photo will be removed.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.error,
              ),
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await FirestoreService.instance
          .removeProfileImage(_farmId!);

      _showSnack('Farm photo removed.');
    } catch (e) {
      _showSnack(
        FirestoreService.instance.describeError(e),
        isError: true,
      );
    }
  }

  void _showPhotoOptions() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(28),
        ),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.photo_library_outlined,
                  color: AppColors.primaryGreen,
                ),
                title: const Text('Change photo'),
                subtitle: const Text(
                  'Choose a new photo from your device',
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickPhoto();
                },
              ),
              if (_farm?.profileImage != null)
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline,
                    color: AppColors.error,
                  ),
                  title: const Text(
                    'Remove photo',
                    style: TextStyle(
                      color: AppColors.error,
                    ),
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

  Future<void> _showBillSettings() async {
    if (_farmId == null) return;

    final current =
        _farm?.billSettings ?? const BillSettings();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.paleGreen,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(28),
        ),
      ),
      builder: (_) {
        return _BillSettingsSheet(
          farmId: _farmId!,
          initialSettings: current,
        );
      },
    );
  }

  Future<void> _showAddPartnerSheet() async {
    if (_farmId == null) return;

    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.paleGreen,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(28),
        ),
      ),
      builder: (_) {
        return _AddPartnerSheet(
          farmId: _farmId!,
        );
      },
    );

    if (added == true) {
      _showSnack('Partner added successfully.');
    }
  }


  Future<void> _confirmRemovePartner(
      PartnerModel partner,
      ) async {
    if (_farmId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Remove partner?'),
          content: Text(
            '${partner.name} will no longer be listed as a farm partner.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.error,
              ),
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await FirestoreService.instance.deletePartner(
        farmId: _farmId!,
        partnerId: partner.id,
      );

      _showSnack('Partner removed.');
    } catch (e) {
      _showSnack(
        FirestoreService.instance.describeError(e),
        isError: true,
      );
    }
  }

  Future<void> _changeLanguage(
      AppLanguage language,
      ) async {
    if (_farmId == null) return;

    try {
      await context
          .read<LocaleProvider>()
          .setLanguage(language);

      await FirestoreService.instance.updatePreferredLanguage(
        _farmId!,
        language.code,
      );

      _showSnack('Language updated.');
    } catch (e) {
      _showSnack(
        'Could not update language.',
        isError: true,
      );
    }
  }

  Future<void> _logout() async {
    if (_loggingOut) return;

    setState(() {
      _loggingOut = true;
    });

    try {
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const LoginScreen(),
        ),
            (_) => false,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _loggingOut = false;
        });

        _showSnack(
          'Could not sign out. Please try again.',
          isError: true,
        );
      }
    }
  }

  void _onBottomNavTap(int index) {
    switch (index) {
      case 4:
        return;

      case 3:
        Navigator.of(context).pop();
        Navigator.of(context).push(
          fastRoute(
            const CustomerManagementScreen(),
          ),
        );
        break;

      case 0:
        Navigator.of(context).pop();
        break;

      case 1:
        Navigator.of(context).pop();
        Navigator.of(context).push(
          fastRoute(
            const PalaiScreen(),
          ),
        );
        break;

      case 2:
        Navigator.of(context).pop();
        Navigator.of(context).push(
          fastRoute(
            const StockScreen(),
          ),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.paleGreen,
        bottomNavigationBar: AppBottomNav(
          currentIndex: 4,
          onTap: _onBottomNavTap,
        ),
        body: const Center(
          child: CircularProgressIndicator(
            color: AppColors.primaryGreen,
          ),
        ),
      );
    }

    final farm = _farm;

    final farmName =
    farm?.farmName.trim().isNotEmpty == true
        ? farm!.farmName
        : 'My Goat Farms';

    final ownerName = farm?.ownerName ?? '';

    return PopScope(
      canPop: !_hasUnsavedDetails,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        final canLeave =
        await _confirmLeaveIfNeeded();

        if (canLeave && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.paleGreen,
        bottomNavigationBar: AppBottomNav(
          currentIndex: 4,
          onTap: _onBottomNavTap,
        ),
        body: SafeArea(
          child: RefreshIndicator(
            color: AppColors.primaryGreen,
            onRefresh: () async {
              final uid =
                  FirebaseAuth.instance.currentUser?.uid;

              if (uid == null) return;

              final farm =
              await FirestoreService.instance
                  .getFarmByAuthUid(uid);

              if (farm == null || !mounted) return;

              setState(() {
                _farm = farm;
              });
            },
            child: SingleChildScrollView(
              physics:
              const AlwaysScrollableScrollPhysics(),
              padding:
              const EdgeInsets.only(bottom: 32),
              child: Column(
                children: [
                  FadeInDown(
                    duration:
                    const Duration(milliseconds: 220),
                    child: _buildHeader(
                      farmName,
                      ownerName,
                    ),
                  ),

                  Padding(
                    padding:
                    const EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      0,
                    ),
                    child: Column(
                      children: [
                        _buildCompletionCard(),

                        const SizedBox(height: 16),

                        _buildYourDetailsCard(farm),

                        const SizedBox(height: 16),

                        _buildFarmTeamCard(),

                        const SizedBox(height: 16),

                        _buildLanguageCard(),

                        const SizedBox(height: 16),

                        _buildBillDetailsCard(farm),

                        const SizedBox(height: 20),

                        _buildAccountCard(),

                        const SizedBox(height: 20),

                        _buildLogoutButton(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
      String farmName,
      String ownerName,
      ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        20,
        8,
        20,
        28,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: AppColors.headerGradient,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () async {
                  final canLeave =
                  await _confirmLeaveIfNeeded();

                  if (canLeave && mounted) {
                    Navigator.of(context).maybePop();
                  }
                },
                icon: const Icon(
                  Icons.arrow_back,
                  color: Colors.white,
                ),
              ),
              Expanded(
                child: Text(
                  AppStrings.t(
                    context,
                    'profile_title',
                  ),
                  textAlign: TextAlign.center,
                  style: AppTheme.heading(
                    size: 17,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),

          const SizedBox(height: 8),

          GestureDetector(
            onTap: _showPhotoOptions,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(
                      color: Colors.white,
                      width: 3,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        blurRadius: 16,
                        offset: Offset(0, 6),
                        color: Colors.black26,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: _farm?.profileImage != null
                        ? Image.memory(
                      _farm!.profileImage!,
                      fit: BoxFit.cover,
                    )
                        : const Icon(
                      Icons.pets,
                      color:
                      AppColors.primaryGreen,
                      size: 42,
                    ),
                  ),
                ),

                if (_uploadingPhoto)
                  Container(
                    width: 100,
                    height: 100,
                    decoration:
                    const BoxDecoration(
                      color: Colors.black38,
                      shape: BoxShape.circle,
                    ),
                    child:
                    const CircularProgressIndicator(
                      color: Colors.white,
                    ),
                  ),

                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.darkGreen,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          Text(
            farmName,
            textAlign: TextAlign.center,
            style: AppTheme.heading(
              size: 19,
              color: Colors.white,
            ),
          ),

          if (ownerName.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              ownerName,
              style: AppTheme.body(
                size: 13,
                color: Colors.white.withOpacity(.9),
              ),
            ),
          ],

          const SizedBox(height: 7),

          Text(
            'Tap the photo to change it',
            style: AppTheme.body(
              size: 11,
              color: Colors.white.withOpacity(.75),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletionCard() {
    final percent = _percent;
    final complete = percent >= 100;

    return Container(
      decoration: AppTheme.card(radius: 20),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: percent / 100,
                  strokeWidth: 6,
                  backgroundColor:
                  AppColors.lightGreen,
                  color: complete
                      ? AppColors.success
                      : AppColors.primaryGreen,
                ),
                Text(
                  '$percent%',
                  style: AppTheme.heading(
                    size: 13,
                    color: AppColors.darkGreen,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  complete
                      ? 'Profile complete 🎉'
                      : 'Complete your profile',
                  style: AppTheme.heading(size: 15),
                ),
                const SizedBox(height: 5),
                Text(
                  complete
                      ? 'Everything important is configured.'
                      : 'Complete the remaining details to finish setup.',
                  style: AppTheme.body(size: 12),
                ),
              ],
            ),
          ),

          if (complete)
            const Icon(
              Icons.verified,
              color: AppColors.success,
            ),
        ],
      ),
    );
  }

  Widget _buildYourDetailsCard(
      FarmModel? farm,
      ) {
    return _sectionCard(
      title: 'Farm Details',
      icon: Icons.storefront_outlined,
      child: Column(
        children: [
          _input(
            controller: _farmNameController,
            label: 'Farm name',
            hint: 'Enter your farm name',
            icon: Icons.storefront_outlined,
          ),

          const SizedBox(height: 12),

          _input(
            controller: _ownerNameController,
            label: 'Owner name',
            hint: 'Enter owner name',
            icon: Icons.person_outline,
          ),

          const SizedBox(height: 12),

          _lockedField(
            label: 'Mobile number',
            value: farm?.mobileNumber ?? '',
            icon: Icons.phone_outlined,
          ),

          const SizedBox(height: 12),

          _lockedField(
            label: 'Email',
            value: farm?.email ?? '',
            icon: Icons.email_outlined,
          ),

          const SizedBox(height: 12),

          _input(
            controller: _addressController,
            label: 'Farm address',
            hint: 'Enter complete farm address',
            icon: Icons.location_on_outlined,
            maxLines: 3,
          ),

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed:
              _savingDetails ? null : _saveDetails,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                AppColors.primaryGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius.circular(30),
                ),
              ),
              child: _savingDetails
                  ? const SizedBox(
                width: 21,
                height: 21,
                child:
                CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
                  : const Text(
                'Save Farm Details',
                style: TextStyle(
                  fontWeight:
                  FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFarmTeamCard() {
    return _sectionCard(
      title: 'Farm Team',
      icon: Icons.groups_outlined,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _partners.isEmpty
                      ? 'No partners added yet'
                      : '${_partners.length} partner${_partners.length == 1 ? '' : 's'}',
                  style: AppTheme.body(
                    size: 13,
                    color: AppColors.textGrey,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _showAddPartnerSheet,
                icon: const Icon(
                  Icons.person_add_alt_1,
                  size: 17,
                ),
                label: const Text('Add'),
              ),
            ],
          ),

          if (_partners.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(),
            const SizedBox(height: 8),

            ..._partners.map(
                  (partner) => _buildPartnerTile(
                partner,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPartnerTile(
      PartnerModel partner,
      ) {
    return Padding(
      padding:
      const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 20,
            backgroundColor:
            AppColors.lightGreen,
            child: Icon(
              Icons.person,
              color: AppColors.primaryGreen,
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  partner.name,
                  style: AppTheme.body(
                    size: 13,
                    color: AppColors.textDark,
                    weight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  partner.mobileNumber,
                  style: AppTheme.body(size: 11),
                ),
              ],
            ),
          ),

          IconButton(
            tooltip: 'Remove partner',
            onPressed: () =>
                _confirmRemovePartner(partner),
            icon: const Icon(
              Icons.delete_outline,
              color: AppColors.error,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageCard() {
    final current =
        context.watch<LocaleProvider>().language;

    return _sectionCard(
      title: 'App Language',
      icon: Icons.language_outlined,
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Text(
            'Choose the language used throughout the application.',
            style: AppTheme.body(size: 12),
          ),

          const SizedBox(height: 14),

          Row(
            children: AppLanguage.values.map(
                  (language) {
                final selected =
                    language == current;

                return Expanded(
                  child: Padding(
                    padding:
                    const EdgeInsets.symmetric(
                      horizontal: 4,
                    ),
                    child: GestureDetector(
                      onTap: () =>
                          _changeLanguage(
                            language,
                          ),
                      child: AnimatedContainer(
                        duration:
                        const Duration(
                          milliseconds: 180,
                        ),
                        padding:
                        const EdgeInsets
                            .symmetric(
                          vertical: 13,
                        ),
                        decoration:
                        BoxDecoration(
                          color: selected
                              ? AppColors
                              .primaryGreen
                              : const Color(
                            0xFFF1F3F1,
                          ),
                          borderRadius:
                          BorderRadius.circular(
                            14,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            language.label,
                            style:
                            AppTheme.heading(
                              size: 13,
                              color: selected
                                  ? Colors.white
                                  : AppColors
                                  .textDark,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildBillDetailsCard(
      FarmModel? farm,
      ) {
    final settings =
        farm?.billSettings ?? const BillSettings();

    return _sectionCard(
      title: 'Bill Details',
      icon: Icons.receipt_long_outlined,
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Text(
            'These details appear on Palai check-out bills.',
            style: AppTheme.body(size: 12),
          ),

          const SizedBox(height: 14),

          Container(
            width: double.infinity,
            padding:
            const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F3F1),
              borderRadius:
              BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  settings.businessName,
                  style: AppTheme.body(
                    size: 14,
                    color: AppColors.textDark,
                    weight: FontWeight.w700,
                  ),
                ),

                if (settings.tagline
                    .trim()
                    .isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    settings.tagline,
                    style:
                    AppTheme.body(size: 11),
                  ),
                ],

                if (settings.address
                    .trim()
                    .isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    settings.address,
                    style:
                    AppTheme.body(size: 11),
                  ),
                ],

                if (settings.phone
                    .trim()
                    .isNotEmpty)
                  Text(
                    'Phone: ${settings.phone}',
                    style:
                    AppTheme.body(size: 11),
                  ),

                if (settings.upiId
                    .trim()
                    .isNotEmpty)
                  Text(
                    'UPI: ${settings.upiId}',
                    style:
                    AppTheme.body(size: 11),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _showBillSettings,
              icon: const Icon(
                Icons.edit_outlined,
              ),
              label: const Text(
                'Edit Bill Details',
              ),
              style:
              OutlinedButton.styleFrom(
                foregroundColor:
                AppColors.primaryGreen,
                side: const BorderSide(
                  color:
                  AppColors.primaryGreen,
                ),
                shape:
                RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius.circular(
                    30,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard() {
    return _sectionCard(
      title: 'Account',
      icon: Icons.manage_accounts_outlined,
      child: Column(
        children: [
          _actionTile(
            icon: Icons.security_outlined,
            title: 'Account security',
            subtitle:
            'Your login email and mobile are protected',
            trailing: const Icon(
              Icons.lock_outline,
              size: 19,
            ),
          ),

          const Divider(),

          _actionTile(
            icon: Icons.refresh_outlined,
            title: 'Refresh profile',
            subtitle:
            'Pull the latest farm information',
            trailing: const Icon(
              Icons.chevron_right,
            ),
            onTap: () async {
              await _refreshFarm();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _refreshFarm() async {
    final uid =
        FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) return;

    try {
      final farm =
      await FirestoreService.instance
          .getFarmByAuthUid(uid);

      if (!mounted || farm == null) return;

      setState(() {
        _farm = farm;
      });

      _showSnack('Profile refreshed.');
    } catch (e) {
      _showSnack(
        FirestoreService.instance.describeError(e),
        isError: true,
      );
    }
  }

  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed:
        _loggingOut ? null : _logout,
        icon: _loggingOut
            ? const SizedBox(
          width: 18,
          height: 18,
          child:
          CircularProgressIndicator(
            strokeWidth: 2,
          ),
        )
            : const Icon(
          Icons.logout,
          color: AppColors.error,
        ),
        label: Text(
          _loggingOut
              ? 'Signing out...'
              : 'Sign out',
          style: AppTheme.heading(
            size: 14,
            color: AppColors.error,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(
            color: AppColors.error,
          ),
          shape: RoundedRectangleBorder(
            borderRadius:
            BorderRadius.circular(30),
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      decoration: AppTheme.card(radius: 20),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color:
                  AppColors.lightGreen,
                  borderRadius:
                  BorderRadius.circular(11),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color:
                  AppColors.primaryGreen,
                ),
              ),

              const SizedBox(width: 11),

              Text(
                title,
                style: AppTheme.heading(
                  size: 15,
                  color: AppColors.darkGreen,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          child,
        ],
      ),
    );
  }

  Widget _input({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      textInputAction: maxLines > 1
          ? TextInputAction.newline
          : TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(
          icon,
          color: AppColors.primaryGreen,
        ),
      ),
    );
  }

  Widget _lockedField({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      width: double.infinity,
      padding:
      const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 13,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F1),
        borderRadius:
        BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: AppColors.textGrey,
            size: 20,
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTheme.body(
                    size: 10,
                    color: AppColors.textGrey,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value.isEmpty ? '—' : value,
                  style: AppTheme.body(
                    size: 13,
                    color: AppColors.textDark,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          const Icon(
            Icons.lock_outline,
            size: 16,
            color: AppColors.textGrey,
          ),
        ],
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Icon(
        icon,
        color: AppColors.primaryGreen,
      ),
      title: Text(
        title,
        style: AppTheme.body(
          size: 13,
          color: AppColors.textDark,
          weight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: AppTheme.body(size: 11),
      ),
      trailing: trailing,
    );
  }
}

class _BillSettingsSheet extends StatefulWidget {
  final String farmId;
  final BillSettings initialSettings;

  const _BillSettingsSheet({
    required this.farmId,
    required this.initialSettings,
  });

  @override
  State<_BillSettingsSheet> createState() =>
      _BillSettingsSheetState();
}

class _BillSettingsSheetState
    extends State<_BillSettingsSheet> {
  late final TextEditingController _businessName;
  late final TextEditingController _tagline;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  late final TextEditingController _upi;
  late final TextEditingController _footer;
  late final TextEditingController _terms;

  bool _saving = false;

  @override
  void initState() {
    super.initState();

    final s = widget.initialSettings;

    _businessName =
        TextEditingController(text: s.businessName);

    _tagline =
        TextEditingController(text: s.tagline);

    _address =
        TextEditingController(text: s.address);

    _phone =
        TextEditingController(text: s.phone);

    _upi =
        TextEditingController(text: s.upiId);

    _footer =
        TextEditingController(text: s.footerNote);

    _terms =
        TextEditingController(text: s.terms);
  }

  @override
  void dispose() {
    _businessName.dispose();
    _tagline.dispose();
    _address.dispose();
    _phone.dispose();
    _upi.dispose();
    _footer.dispose();
    _terms.dispose();

    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;

    final businessName =
    _businessName.text.trim();

    if (businessName.isEmpty) {
      _showError(
        'Business name cannot be empty.',
      );
      return;
    }

    final phone = _phone.text.trim();

    if (phone.isNotEmpty &&
        !RegExp(
          r'^[0-9+\-\s()]{7,20}$',
        ).hasMatch(phone)) {
      _showError(
        'Please enter a valid phone number.',
      );
      return;
    }

    final upi = _upi.text.trim();

    if (upi.isNotEmpty &&
        !RegExp(
          r'^[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+$',
        ).hasMatch(upi)) {
      _showError(
        'Please enter a valid UPI ID.',
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    final settings = BillSettings(
      businessName: businessName,
      tagline: _tagline.text.trim(),
      address: _address.text.trim(),
      phone: phone,
      upiId: upi,
      footerNote:
      _footer.text.trim().isEmpty
          ? 'Thank you for trusting us with your goat.'
          : _footer.text.trim(),
      terms: _terms.text.trim(),
    );

    try {
      await FirestoreService.instance
          .updateBillSettings(
        widget.farmId,
        settings,
      );

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (e) {
      _showError(
        FirestoreService.instance.describeError(e),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final bottom =
        MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        bottom: bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            20,
            4,
            20,
            24,
          ),
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Text(
                'Bill Details',
                style: AppTheme.heading(
                  size: 20,
                  color: AppColors.darkGreen,
                ),
              ),

              const SizedBox(height: 5),

              Text(
                'These details appear on Palai check-out bills.',
                style: AppTheme.body(size: 12),
              ),

              const SizedBox(height: 20),

              _billField(
                controller: _businessName,
                label: 'Business name',
                hint: 'My Goat Farms',
                icon:
                Icons.business_outlined,
              ),

              const SizedBox(height: 12),

              _billField(
                controller: _tagline,
                label: 'Tagline',
                hint:
                'Palai - Goat Boarding & Care',
                icon:
                Icons.short_text_outlined,
              ),

              const SizedBox(height: 12),

              _billField(
                controller: _address,
                label: 'Address',
                hint: 'Farm address',
                icon:
                Icons.location_on_outlined,
                maxLines: 3,
              ),

              const SizedBox(height: 12),

              _billField(
                controller: _phone,
                label: 'Phone',
                hint: '+91 90000 00000',
                icon:
                Icons.phone_outlined,
                keyboardType:
                TextInputType.phone,
              ),

              const SizedBox(height: 12),

              _billField(
                controller: _upi,
                label: 'UPI ID',
                hint: 'mygoatfarms@upi',
                icon:
                Icons.account_balance_outlined,
              ),

              const SizedBox(height: 12),

              _billField(
                controller: _footer,
                label: 'Thank-you note',
                hint:
                'Thank you for trusting us with your goat.',
                icon:
                Icons.favorite_border,
                maxLines: 2,
              ),

              const SizedBox(height: 12),

              _billField(
                controller: _terms,
                label: 'Terms & conditions',
                hint:
                'Optional terms printed on the bill',
                icon:
                Icons.description_outlined,
                maxLines: 4,
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed:
                  _saving ? null : _save,
                  style:
                  ElevatedButton.styleFrom(
                    backgroundColor:
                    AppColors.primaryGreen,
                    foregroundColor:
                    Colors.white,
                    shape:
                    RoundedRectangleBorder(
                      borderRadius:
                      BorderRadius.circular(
                        30,
                      ),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                    width: 21,
                    height: 21,
                    child:
                    CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                      : const Text(
                    'Save Bill Details',
                    style: TextStyle(
                      fontWeight:
                      FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _billField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(
          icon,
          color: AppColors.primaryGreen,
        ),
      ),
    );
  }
}

class _AddPartnerSheet extends StatefulWidget {
  final String farmId;

  const _AddPartnerSheet({
    required this.farmId,
  });

  @override
  State<_AddPartnerSheet> createState() =>
      _AddPartnerSheetState();
}

class _AddPartnerSheetState extends State<_AddPartnerSheet> {
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _saving = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _createPartner() async {
    if (_saving) return;

    final name = _nameController.text.trim();
    final mobile = _mobileController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (name.isEmpty) {
      _showError('Please enter partner name.');
      return;
    }

    if (mobile.isEmpty) {
      _showError('Please enter partner mobile number.');
      return;
    }

    if (email.isEmpty) {
      _showError('Please enter partner email.');
      return;
    }

    if (password.length < 6) {
      _showError(
        'Password must be at least 6 characters.',
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      // Create the Firebase Auth account using
      // the secondary Firebase app so the owner
      // remains logged in.
      final authUid =
      await PartnerAuthService.instance.createPartnerAccount(
        email: email,
        password: password,
      );

      // Create the partner document.
      final partnerId =
      await FirestoreService.instance.createPartner(
        widget.farmId,
        name: name,
        mobileNumber: mobile,
        email: email,
        authUid: authUid,
      );

      if (!mounted) return;

      // Close the Add Partner sheet first.
      Navigator.pop(context, true);

      // Open permission configuration.
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PartnerPermissionsScreen(
            farmId: widget.farmId,
            partnerId: partnerId,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      _showError(
        FirestoreService.instance.describeError(e),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final bottom =
        MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            20,
            8,
            20,
            24,
          ),
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Text(
                'Add Farm Partner',
                style: AppTheme.heading(
                  size: 20,
                  color: AppColors.darkGreen,
                ),
              ),

              const SizedBox(height: 5),

              Text(
                'Create a partner account and configure their access.',
                style: AppTheme.body(size: 12),
              ),

              const SizedBox(height: 20),

              _partnerField(
                controller: _nameController,
                label: 'Partner name',
                hint: 'Enter partner name',
                icon: Icons.person_outline,
              ),

              const SizedBox(height: 12),

              _partnerField(
                controller: _mobileController,
                label: 'Mobile number',
                hint: '+91 90000 00000',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
              ),

              const SizedBox(height: 12),

              _partnerField(
                controller: _emailController,
                label: 'Email',
                hint: 'partner@example.com',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
              ),

              const SizedBox(height: 12),

              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Temporary password',
                  hintText: 'Minimum 6 characters',
                  prefixIcon: const Icon(
                    Icons.lock_outline,
                    color: AppColors.primaryGreen,
                  ),
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() {
                        _obscurePassword =
                        !_obscurePassword;
                      });
                    },
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed:
                  _saving ? null : _createPartner,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                    AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                      BorderRadius.circular(30),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                    width: 21,
                    height: 21,
                    child:
                    CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                      : const Text(
                    'Create Partner',
                    style: TextStyle(
                      fontWeight:
                      FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _partnerField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(
          icon,
          color: AppColors.primaryGreen,
        ),
      ),
    );
  }
}