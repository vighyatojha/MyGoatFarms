import 'dart:async';

import 'package:animate_do/animate_do.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_theme.dart';
import '../../l10n/app_strings.dart';
import '../../models/bill_settings_model.dart';
import '../../models/farm_model.dart';
import '../../models/health_reminder_settings_model.dart';
import '../../models/partner_model.dart';
import '../../services/firestore_service.dart';
import '../../services/image_service.dart';
import '../../services/locale_provider.dart';
import '../../services/notification_service.dart';
import '../../services/partner_auth_service.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/farm_not_linked_state.dart';
import '../login_screen.dart';
import 'profile_partner_dashboard.dart';
import 'bill_settings_screen.dart';
import 'health_reminder_settings_screen.dart';

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

  /// True when the signed-in account is the farm owner, false when it's a
  /// partner. Defaults to true so nothing changes for the (much more
  /// common) owner path while resolution is still in flight; only ever
  /// flipped to false once we've confirmed the uid resolves via a partner
  /// record rather than the farm's own `authUid`.
  bool _isOwner = true;

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

      // Resolve BOTH the owner and partner case — using the owner-only
      // getFarmByAuthUid() here left a partner's _farmId permanently null
      // (crashing later on the ProfilePartnerDashboard(farmId: _farmId!)
      // below) and always rendered the owner-only sections since isOwner
      // was never set to false.
      var farm = await FirestoreService.instance.getFarmByAuthUid(uid);
      var isOwner = true;

      if (farm == null) {
        final partner = await FirestoreService.instance.getPartnerByAuthUid(uid);
        if (partner != null && partner.farmId.isNotEmpty) {
          farm = await FirestoreService.instance.getFarmById(partner.farmId);
          isOwner = false;
        }
      }

      if (!mounted) return;

      if (farm == null) {
        setState(() => _loading = false);
        return;
      }

      _isOwner = isOwner;
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
    // Defense in depth: the "Save Farm Details" button is hidden for
    // partners (see _buildYourDetailsCard), but guard the method itself
    // too in case it's ever reachable another way.
    if (!_isOwner) return;
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
    // Defense in depth: the photo-edit affordance is hidden for partners
    // (see _buildHeader), but guard the method itself too in case it's
    // ever reachable another way.
    if (!_isOwner) return;
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
    // Defense in depth: the photo-edit affordance is hidden for partners
    // (see _buildHeader), but guard the method itself too in case it's
    // ever reachable another way.
    if (!_isOwner) return;
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
    // Defense in depth: the header's GestureDetector no longer calls this
    // for partners (see _buildHeader), but guard it here too in case it's
    // ever reachable another way.
    if (!_isOwner) return;

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
    if (!_isOwner) return;
    if (_farmId == null) return;

    final current = (_farm?.billSettings ?? const BillSettings()).copyWith(
      email: (_farm?.billSettings?.email.trim().isNotEmpty ?? false)
          ? _farm!.billSettings!.email
          : (_farm?.email ?? ''),
    );

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BillSettingsScreen(
          farmId: _farmId!,
          initialSettings: current,
        ),
      ),
    );
  }

  /// Opens the farm-level Health Reminder Settings editor — Vaccination,
  /// Hoof Cutting, and Hair Trimming reminder cadences that apply to
  /// every active goat in this farm regardless of customer. See
  /// [HealthReminderSettingsScreen].
  Future<void> _showHealthReminderSettings() async {
    if (!_isOwner) return;
    if (_farmId == null) return;

    final current = _farm?.healthReminderSettings ?? HealthReminderSettings.defaults;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HealthReminderSettingsScreen(
          farmId: _farmId!,
          initialSettings: current,
        ),
      ),
    );
  }

  Future<void> _showAddPartnerSheet() async {
    // Defense in depth: ProfilePartnerDashboard already only renders the
    // "Add Partner" button when isOwner is true, but guard the method
    // itself too in case it's ever reachable another way.
    if (!_isOwner) return;
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

  Future<void> _logout() async {
    if (_loggingOut) return;

    setState(() {
      _loggingOut = true;
    });

    try {
      await NotificationService.instance.disableForCurrentFarm();

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

  // Home/Palai/Stock/Customers (indices 0-3) all live side-by-side inside
  // MainShell's IndexedStack under ONE shared AppBottomNav. They were
  // previously re-pushed here as brand-new, standalone screens, which is
  // why the bottom nav disappeared after Profile -> Customer Management
  // (and would have for Palai/Stock too): those screens have no
  // bottomNavigationBar of their own, they rely entirely on MainShell for
  // it. The fix is to pop back to the shell and tell it which tab to
  // show, instead of pushing a second, nav-less copy of the screen.
  //
  // The unsaved-changes confirmation is handled once, centrally, by the
  // PopScope below (it intercepts this pop the same way it intercepts the
  // system back button), so this just requests the pop with the chosen
  // tab index as the result.
  void _onBottomNavTap(int index) {
    // We are already showing Profile, so tapping Profile again should be a
    // no-op — mirrors MainShell._navigateToTab's "already on this screen"
    // guard. (This used to check `index == 4`, which is Finance's shell
    // index, not Profile's — that was blocking Finance from ever being
    // reachable from here, and it's what let currentIndex stay wrong too.)
    if (index == 5) return;

    Navigator.of(context).pop(index);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.paleGreen,
        bottomNavigationBar: AppBottomNav(
          currentIndex: 5,
          onTap: _onBottomNavTap,
        ),
        body: const Center(
          child: CircularProgressIndicator(
            color: AppColors.primaryGreen,
          ),
        ),
      );
    }

    // Resolution finished but this account isn't linked to any farm as
    // either an owner or a partner — same fallback as HomeScreen, instead
    // of falling through and crashing on ProfilePartnerDashboard's
    // `farmId: _farmId!` below.
    if (_farmId == null) {
      return Scaffold(
        backgroundColor: AppColors.paleGreen,
        bottomNavigationBar: AppBottomNav(
          currentIndex: 5,
          onTap: _onBottomNavTap,
        ),
        body: SafeArea(
          child: Center(
            child: FarmNotLinkedState(
              onRetry: () {
                setState(() => _loading = true);
                _init();
              },
            ),
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
          // Forward whatever result the blocked pop was carrying (e.g.
          // the tab index from _onBottomNavTap) instead of dropping it,
          // so confirming "leave without saving" still lands on the
          // right tab rather than just the previous one.
          Navigator.of(context).pop(result);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.paleGreen,
        bottomNavigationBar: AppBottomNav(
          currentIndex: 5,
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
                  .getFarmForUser(uid);

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
                        FadeInUp(
                          duration: const Duration(milliseconds: 260),
                          child: _buildYourDetailsCard(farm),
                        ),

                        const SizedBox(height: 12),

                        ProfilePartnerDashboard(
                          farmId: _farmId!,
                          partners: _partners,
                          isOwner: _isOwner,
                          onAddPartner: _showAddPartnerSheet,
                        ),

                        const SizedBox(height: 12),

                        _buildSettingsCard(),

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
    final percent = _percent;
    final complete = percent >= 100;
    final role = _isOwner ? 'OWNER' : 'PARTNER';
    final roleSubtitle = _isOwner ? 'Super Admin' : 'Farm Partner';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: const BoxDecoration(
        color: AppColors.paleGreen,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      farmName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.heading(
                        size: 22,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Account & Farm Settings',
                      style: AppTheme.body(size: 10, color: AppColors.textGrey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: AppTheme.card(radius: 18),
            child: Column(
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: _isOwner ? _showPhotoOptions : null,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.lightGreen,
                              border: Border.all(
                                color: Colors.white,
                                width: 2,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: _farm?.profileImage != null
                                ? Image.memory(_farm!.profileImage!, fit: BoxFit.cover)
                                : const Icon(
                              Icons.home_work_outlined,
                              color: AppColors.primaryGreen,
                              size: 26,
                            ),
                          ),
                          if (_isOwner)
                            Positioned(
                              right: -1,
                              bottom: -1,
                              child: Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: AppColors.primaryGreen,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 1.5),
                                ),
                                child: const Icon(
                                  Icons.add,
                                  color: Colors.white,
                                  size: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  farmName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTheme.heading(size: 15.5),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.lightGreen,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  role,
                                  style: const TextStyle(
                                    color: AppColors.primaryGreen,
                                    fontSize: 7,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: .5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            ownerName.trim().isEmpty ? roleSubtitle : '$ownerName ($roleSubtitle)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.body(size: 10, color: AppColors.textGrey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: AppColors.lightGreen,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        complete ? Icons.check : Icons.check,
                        size: 13,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Profile ${complete ? 'Complete' : 'Progress'} $percent%',
                        style: AppTheme.body(
                          size: 10,
                          color: AppColors.textDark,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: complete ? AppColors.lightGreen : const Color(0xFFF3F6F4),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        complete ? 'Verified' : 'Complete setup',
                        style: TextStyle(
                          color: complete ? AppColors.primaryGreen : AppColors.textGrey,
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildCompletionCard() {
    final percent = _percent;
    final complete = percent >= 100;

    // AnimatedSwitcher gives the card a proper transition every time it
    // "appears/returns" — first build, coming back from another screen
    // with a saved change, or flipping between "in progress" and
    // "complete" — instead of the text/icon just snapping in place.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: Container(
        // Keying on `complete` (rather than percent) is what drives the
        // AnimatedSwitcher transition above — it re-plays whenever the
        // profile flips between "in progress" and "complete", not on
        // every tiny percent change.
        key: ValueKey<bool>(complete),
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
                  // TweenAnimationBuilder smoothly animates the ring and
                  // the number from the old percent to the new one
                  // whenever `percent` changes, instead of jumping
                  // straight to the new value.
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                      begin: 0,
                      end: percent.toDouble(),
                    ),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    builder: (context, animatedPercent, _) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: animatedPercent / 100,
                            strokeWidth: 6,
                            backgroundColor:
                            AppColors.lightGreen,
                            color: complete
                                ? AppColors.success
                                : AppColors.primaryGreen,
                          ),
                          Text(
                            '${animatedPercent.round()}%',
                            style: AppTheme.heading(
                              size: 13,
                              color: AppColors.darkGreen,
                            ),
                          ),
                        ],
                      );
                    },
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
              ZoomIn(
                duration: const Duration(milliseconds: 350),
                child: const Icon(
                  Icons.verified,
                  color: AppColors.success,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildYourDetailsCard(FarmModel? farm) {
    return _sectionCard(
      title: 'Farm Information',
      icon: Icons.storefront_outlined,
      trailing: _isOwner
          ? TextButton(
        onPressed: _showEditFarmDetails,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: const Text(
          'Edit',
          style: TextStyle(
            color: AppColors.primaryGreen,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      )
          : null,
      child: Column(
        children: [
          _infoRow(
            Icons.phone_outlined,
            'MOBILE',
            farm?.mobileNumber ?? '',
            verified: true,
          ),
          const SizedBox(height: 8),
          _infoRow(
            Icons.email_outlined,
            'EMAIL ADDRESS',
            farm?.email ?? '',
            verified: true,
          ),
          const SizedBox(height: 8),
          _infoRow(
            Icons.location_on_outlined,
            'FARM ADDRESS',
            farm?.address ?? '',
            trailing: 'Primary',
          ),
          if (_isOwner) ...[
            const SizedBox(height: 11),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: FilledButton.icon(
                onPressed: _showEditFarmDetails,
                icon: const Icon(Icons.edit_outlined, size: 14),
                label: const Text(
                  'Update Farm Details',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
  Widget _buildBillDetailsCard(FarmModel? farm) {
    return _actionTile(
      icon: Icons.receipt_long_outlined,
      title: 'Bill & Invoice Settings',
      subtitle: 'Configure bill details, terms, notes and branding',
      trailing: const Icon(Icons.chevron_right_rounded, size: 19),
      onTap: _isOwner ? _showBillSettings : null,
    );
  }
  /// Vaccination / Hoof Cutting / Hair Trimming reminder schedules for
  /// the whole farm — see [HealthReminderSettingsScreen]. Applies to
  /// every active goat regardless of customer.
  Widget _buildHealthReminderSettingsCard(FarmModel? farm) {
    return _actionTile(
      icon: Icons.health_and_safety_outlined,
      title: 'Health Reminder Settings',
      subtitle: 'Vaccination, hoof cutting & hair trimming reminders',
      trailing: const Icon(Icons.chevron_right_rounded, size: 19),
      onTap: _isOwner ? _showHealthReminderSettings : null,
    );
  }
  Widget _buildSettingsCard() {
    return _sectionCard(
      title: 'Account',
      icon: Icons.manage_accounts_outlined,
      child: Column(
        children: [
          _buildBillDetailsCard(_farm),
          const Divider(height: 1),
          _buildHealthReminderSettingsCard(_farm),
          const Divider(height: 1),
          _actionTile(
            icon: Icons.lock_outline_rounded,
            title: 'Account Security & PIN',
            subtitle: 'Manage your account security settings',
            trailing: const Icon(Icons.chevron_right_rounded, size: 19),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard() {
    return _buildSettingsCard();
  }

  Future<void> _refreshFarm() async {
    final uid =
        FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) return;

    try {
      final farm =
      await FirestoreService.instance
          .getFarmForUser(uid);

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
    Widget? trailing,
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

              Expanded(
                child: Text(
                  title,
                  style: AppTheme.heading(
                    size: 14,
                    color: AppColors.darkGreen,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),

          const SizedBox(height: 16),

          child,
        ],
      ),
    );
  }

  Widget _infoRow(
      IconData icon,
      String label,
      String value, {
        bool verified = false,
        String? trailing,
      }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9F8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE9EEEB)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textGrey),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 7,
                    color: AppColors.textGrey,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value.isEmpty ? 'Not provided' : value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(
                    size: 10,
                    color: AppColors.textDark,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F2F1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                trailing,
                style: const TextStyle(
                  fontSize: 7,
                  color: AppColors.textGrey,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else if (verified)
            const Icon(
              Icons.verified_outlined,
              size: 15,
              color: AppColors.primaryGreen,
            ),
        ],
      ),
    );
  }

  Future<void> _showEditFarmDetails() async {
    if (!_isOwner || _farmId == null) return;

    final farmNameController = TextEditingController(text: _farmNameController.text);
    final ownerNameController = TextEditingController(text: _ownerNameController.text);
    final addressController = TextEditingController(text: _addressController.text);

    final save = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.paleGreen,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final keyboardBottom = MediaQuery.of(context).viewInsets.bottom;
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + keyboardBottom),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Edit Farm Details', style: AppTheme.heading(size: 19, color: AppColors.darkGreen)),
                    const SizedBox(height: 5),
                    Text('Update the farm information shown on your profile.', style: AppTheme.body(size: 11)),
                    const SizedBox(height: 18),
                    _input(controller: farmNameController, label: 'Farm name', hint: 'Enter your farm name', icon: Icons.storefront_outlined),
                    const SizedBox(height: 11),
                    _input(controller: ownerNameController, label: 'Owner name', hint: 'Enter owner name', icon: Icons.person_outline),
                    const SizedBox(height: 11),
                    _input(controller: addressController, label: 'Farm address', hint: 'Enter complete farm address', icon: Icons.location_on_outlined, maxLines: 3),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: () async {
                          if (farmNameController.text.trim().isEmpty || ownerNameController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              const SnackBar(content: Text('Farm name and owner name cannot be empty.')),
                            );
                            return;
                          }
                          _farmNameController.text = farmNameController.text.trim();
                          _ownerNameController.text = ownerNameController.text.trim();
                          _addressController.text = addressController.text.trim();
                          setSheetState(() {});
                          await _saveDetails();
                          if (sheetContext.mounted) Navigator.pop(sheetContext, true);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryGreen,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    farmNameController.dispose();
    ownerNameController.dispose();
    addressController.dispose();

    if (save == true && mounted) {
      setState(() {});
    }
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

class _AddPartnerSheet extends StatefulWidget {
  final String farmId;

  const _AddPartnerSheet({
    required this.farmId,
  });

  @override
  State<_AddPartnerSheet> createState() => _AddPartnerSheetState();
}

class _AddPartnerSheetState extends State<_AddPartnerSheet> {
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _saving = false;
  bool _obscurePassword = true;
  String? _inlineError;

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
      _showError('Password must be at least 6 characters.');
      return;
    }

    setState(() {
      _saving = true;
      _inlineError = null;
    });

    try {
      // Create the Firebase Auth account using the secondary Firebase app
      // so the owner remains logged in.
      final authUid = await PartnerAuthService.instance.createPartnerAccount(
        email: email,
        password: password,
      );

      // Create the partner document.
      await FirestoreService.instance.createPartner(
        widget.farmId,
        name: name,
        mobileNumber: mobile,
        email: email,
        authUid: authUid,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e, stack) {
      debugPrint('Add Partner failed: $e');
      debugPrint('$stack');

      if (!mounted) return;

      final message = e is FirebaseAuthException && e.message != null
          ? e.message!
          : FirestoreService.instance.describeError(e);

      setState(() {
        _inlineError = message;
      });

      _showError(message);
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

    setState(() {
      _inlineError = message;
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardBottom = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardBottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header — follows the same compact card language as Profile.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.lightGreen,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.person_add_alt_1_rounded,
                        color: AppColors.primaryGreen,
                        size: 23,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add Farm Partner',
                            style: AppTheme.heading(
                              size: 18,
                              color: AppColors.darkGreen,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Create a partner account for your farm team.',
                            style: AppTheme.body(
                              size: 10,
                              color: AppColors.textGrey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Form card — same white rounded-card treatment used by Profile.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: AppTheme.card(radius: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Partner Information',
                      style: AppTheme.heading(
                        size: 13,
                        color: AppColors.darkGreen,
                      ),
                    ),
                    const SizedBox(height: 11),
                    _partnerField(
                      controller: _nameController,
                      label: 'Partner name',
                      hint: 'Enter partner name',
                      icon: Icons.person_outline_rounded,
                    ),
                    const SizedBox(height: 10),
                    _partnerField(
                      controller: _mobileController,
                      label: 'Mobile number',
                      hint: '+91 90000 00000',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 10),
                    _partnerField(
                      controller: _emailController,
                      label: 'Email address',
                      hint: 'partner@example.com',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 10),
                    _passwordField(),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // Small explanatory/security note.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.lightGreen.withOpacity(.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: AppColors.primaryGreen,
                      size: 17,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'The temporary password must contain at least 6 characters. '
                            'The partner can change it later.',
                        style: AppTheme.body(
                          size: 9,
                          color: AppColors.textGrey,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (_inlineError != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.error.withOpacity(.22),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: AppColors.error,
                        size: 17,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _inlineError!,
                          style: AppTheme.body(
                            size: 10,
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _createPartner,
                  icon: _saving
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.2,
                    ),
                  )
                      : const Icon(
                    Icons.person_add_alt_1_rounded,
                    size: 17,
                  ),
                  label: Text(
                    _saving ? 'Creating Partner...' : 'Create Partner',
                    style: AppTheme.body(
                      size: 12,
                      color: Colors.white,
                      weight: FontWeight.w800,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.primaryGreen.withOpacity(.55),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
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
      textInputAction: TextInputAction.next,
      style: AppTheme.body(
        size: 11,
        color: AppColors.textDark,
        weight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: AppTheme.body(
          size: 9,
          color: AppColors.textGrey,
        ),
        hintStyle: AppTheme.body(
          size: 10,
          color: AppColors.textGrey,
        ),
        prefixIcon: Icon(
          icon,
          color: AppColors.primaryGreen,
          size: 18,
        ),
        filled: true,
        fillColor: const Color(0xFFF7F9F8),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 11,
          vertical: 11,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(
            color: Color(0xFFE9EEEB),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(
            color: Color(0xFFE9EEEB),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(
            color: AppColors.primaryGreen,
            width: 1.2,
          ),
        ),
      ),
    );
  }

  Widget _passwordField() {
    return TextField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      textInputAction: TextInputAction.done,
      style: AppTheme.body(
        size: 11,
        color: AppColors.textDark,
        weight: FontWeight.w600,
      ),
      onSubmitted: (_) {
        if (!_saving) _createPartner();
      },
      decoration: InputDecoration(
        labelText: 'Temporary password',
        hintText: 'Minimum 6 characters',
        labelStyle: AppTheme.body(
          size: 9,
          color: AppColors.textGrey,
        ),
        hintStyle: AppTheme.body(
          size: 10,
          color: AppColors.textGrey,
        ),
        prefixIcon: const Icon(
          Icons.lock_outline_rounded,
          color: AppColors.primaryGreen,
          size: 18,
        ),
        suffixIcon: IconButton(
          tooltip: _obscurePassword ? 'Show password' : 'Hide password',
          onPressed: () {
            setState(() {
              _obscurePassword = !_obscurePassword;
            });
          },
          icon: Icon(
            _obscurePassword
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: AppColors.textGrey,
            size: 18,
          ),
        ),
        filled: true,
        fillColor: const Color(0xFFF7F9F8),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 11,
          vertical: 11,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(
            color: Color(0xFFE9EEEB),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(
            color: Color(0xFFE9EEEB),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(
            color: AppColors.primaryGreen,
            width: 1.2,
          ),
        ),
      ),
    );
  }
}