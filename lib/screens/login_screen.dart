import 'dart:typed_data';
import '../../widgets/fast_route.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'checkout_charges_payment_screen.dart';
import '../../app_theme.dart';
import '../../models/palai_models.dart';
import '../../services/firestore_service.dart';

class MultiGoatCheckoutScreen extends StatefulWidget {
  final String customerId;

  /// When opened from Goat List, pass one goat here.
  /// When opened from Customer Profile, leave it empty.
  final List<PalaiGoat> initialSelectedGoats;

  /// true  = user can select multiple goats.
  /// false = direct single-goat checkout.
  final bool allowSelection;

  const MultiGoatCheckoutScreen({
    super.key,
    required this.customerId,
    this.initialSelectedGoats = const [],
    this.allowSelection = true,

  });

  @override
  State<MultiGoatCheckoutScreen> createState() =>
      _MultiGoatCheckoutScreenState();
}

class _MultiGoatCheckoutScreenState
    extends State<MultiGoatCheckoutScreen> {
  final ImagePicker _imagePicker = ImagePicker();

  // ================================================================
  // DATA
  // ================================================================

  List<PalaiGoat> _activeGoats = [];

  final Set<String> _selectedIds = {};

  /// Current farm ID resolved from FirestoreService.
  String? _farmId;

  bool _loading = true;
  String? _error;

  /// 0 = select goats
  /// 1 = checkout details
  /// 2 = review checkout
  int _step = 0;

  final Map<String, _GoatCheckoutData> _details = {};

  @override
  void initState() {
    super.initState();

    // --------------------------------------------------------------
    // Preserve goats passed into this screen.
    //
    // This is used when opening checkout from Goat List:
    // one goat is passed here and selection is disabled.
    // --------------------------------------------------------------
    for (final goat in widget.initialSelectedGoats) {
      _selectedIds.add(goat.id);
      _details[goat.id] =
          _GoatCheckoutData(goat);
    }

    _loadGoats();
  }

  // ================================================================
  // LOAD GOATS
  // ================================================================

  Future<void> _loadGoats() async {
    try {
      // ------------------------------------------------------------
      // GET CURRENT FARM
      // ------------------------------------------------------------

      final farmId =
      await FirestoreService.instance.currentFarmId();

      if (farmId == null) {
        throw Exception(
          'Farm not found.',
        );
      }

      if (!mounted) return;

      // Store the farm ID locally so it can later be passed to
      // Charges & Payment.
      setState(() {
        _farmId = farmId;
      });

      // ------------------------------------------------------------
      // LOAD CUSTOMER GOATS
      // ------------------------------------------------------------

      final goats =
      await FirestoreService.instance
          .goatsForCustomerStream(
        farmId,
        widget.customerId,
      )
          .first;

      if (!mounted) return;

      // Only goats which are currently boarded can be checked out.
      final active = goats
          .where(
            (goat) => !goat.isCheckedOut,
      )
          .toList();

      setState(() {
        _activeGoats = active;
        _loading = false;
      });

      // ------------------------------------------------------------
      // RESTORE / PRESERVE INITIAL SELECTION
      // ------------------------------------------------------------

      for (final goat
      in widget.initialSelectedGoats) {
        final stillActive = active.any(
              (g) => g.id == goat.id,
        );

        if (!stillActive) {
          continue;
        }

        _selectedIds.add(goat.id);

        _details.putIfAbsent(
          goat.id,
              () => _GoatCheckoutData(goat),
        );
      }

      // ------------------------------------------------------------
      // SINGLE GOAT FLOW
      // ------------------------------------------------------------
      //
      // When opened from Goat List:
      //
      // initialSelectedGoats = [selected goat]
      // allowSelection = false
      //
      // Therefore do NOT show Select Goat(s).
      // Go directly to Checkout Details.
      //
      // Customer Profile still uses:
      // allowSelection = true
      //
      // Therefore Customer Profile shows:
      // Select Goat(s) -> Details -> Review
      // ------------------------------------------------------------

      if (!widget.allowSelection &&
          widget.initialSelectedGoats.isNotEmpty) {
        setState(() {
          _step = 1;
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error =
            FirestoreService.instance
                .describeError(e);
      });
    }
  }

  // ================================================================
  // SELECTED GOATS
  // ================================================================

  List<PalaiGoat> get _selectedGoats {
    return _activeGoats
        .where(
          (goat) =>
          _selectedIds.contains(
            goat.id,
          ),
    )
        .toList();
  }

  // ================================================================
  // TOGGLE GOAT
  // ================================================================

  void _toggleGoat(PalaiGoat goat) {
    if (!widget.allowSelection) {
      return;
    }

    setState(() {
      if (_selectedIds.contains(goat.id)) {
        _selectedIds.remove(goat.id);
        _details.remove(goat.id);
      } else {
        _selectedIds.add(goat.id);

        _details[goat.id] =
            _GoatCheckoutData(goat);
      }
    });
  }

  // ================================================================
  // CONTINUE FROM SELECTION
  // ================================================================

  void _continueFromSelection() {
    if (_selectedGoats.isEmpty) {
      _showError(
        'Please select at least one goat.',
      );
      return;
    }

    setState(() {
      _step = 1;
    });
  }

  // ================================================================
  // BACK
  // ================================================================

  void _goBack() {
    if (_step == 0) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _step--;
    });
  }

  // ================================================================
  // CONTINUE FROM DETAILS
  // ================================================================

  void _continueFromDetails() {
    final goats = _selectedGoats;

    if (goats.isEmpty) {
      _showError(
        'No goat selected.',
      );
      return;
    }

    for (final goat in goats) {
      final data =
      _details[goat.id];

      if (data == null) {
        _showError(
          'Checkout details are missing for ${goat.goatCode}.',
        );
        return;
      }

      if (data.finalWeight <= 0) {
        _showError(
          'Please enter a valid final weight for ${goat.goatCode}.',
        );
        return;
      }
    }

    setState(() {
      _step = 2;
    });
  }

  // ================================================================
  // AFTER PHOTO
  // ================================================================

  Future<void> _pickAfterPhoto(
      _GoatCheckoutData data,
      ) async {
    final source =
    await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape:
      const RoundedRectangleBorder(
        borderRadius:
        BorderRadius.vertical(
          top: Radius.circular(22),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding:
            const EdgeInsets.all(20),
            child: Column(
              mainAxisSize:
              MainAxisSize.min,
              children: [
                Text(
                  'Add After Photo',
                  style:
                  AppTheme.heading(
                    size: 17,
                  ),
                ),

                const SizedBox(height: 18),

                Row(
                  children: [
                    Expanded(
                      child:
                      _sourceButton(
                        icon:
                        Icons.camera_alt_rounded,
                        label:
                        'Camera',
                        source:
                        ImageSource.camera,
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child:
                      _sourceButton(
                        icon:
                        Icons.photo_library_rounded,
                        label:
                        'Gallery',
                        source:
                        ImageSource.gallery,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (source == null) {
      return;
    }

    final file =
    await _imagePicker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1600,
    );

    if (file == null) {
      return;
    }

    final bytes =
    await file.readAsBytes();

    if (!mounted) {
      return;
    }

    setState(() {
      data.afterImage = bytes;
    });
  }

  // ================================================================
  // IMAGE SOURCE BUTTON
  // ================================================================

  Widget _sourceButton({
    required IconData icon,
    required String label,
    required ImageSource source,
  }) {
    return OutlinedButton.icon(
      onPressed: () {
        Navigator.of(context)
            .pop(source);
      },
      icon: Icon(icon),
      label: Text(label),
      style:
      OutlinedButton.styleFrom(
        foregroundColor:
        AppColors.darkGreen,
        side:
        const BorderSide(
          color: AppColors.divider,
        ),
        minimumSize:
        const Size.fromHeight(
          50,
        ),
        shape:
        RoundedRectangleBorder(
          borderRadius:
          BorderRadius.circular(
            14,
          ),
        ),
      ),
    );
  }

  // ================================================================
  // ERROR
  // ================================================================

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
        AppColors.error,
      ),
    );
  }

  // ================================================================
  // DISPOSE
  // ================================================================

  @override
  void dispose() {
    for (final data
    in _details.values) {
      data.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.paleGreen,
        appBar: AppBar(
          title: Text(
            'Checkout',
            style: AppTheme.heading(size: 17),
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(
            color: AppColors.primaryGreen,
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: AppColors.paleGreen,
        appBar: AppBar(
          title: Text(
            'Checkout',
            style: AppTheme.heading(size: 17),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: AppColors.error,
                  size: 48,
                ),
                const SizedBox(height: 14),
                Text(
                  'Could not load goats',
                  style: AppTheme.heading(size: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: AppTheme.body(size: 12),
                ),
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _loading = true;
                      _error = null;
                    });

                    _loadGoats();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        title: Text(
          _step == 0
              ? 'Select Goats'
              : _step == 1
              ? 'Checkout Details'
              : 'Review Checkout',
          style: AppTheme.heading(size: 17),
        ),
        leading: IconButton(
          onPressed: _goBack,
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: _buildStep(),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _buildSelection();
      case 1:
        return _buildDetails();
      default:
        return _buildReview();
    }
  }

  // ========================================================================
  // STEP 1 — GOAT SELECTION
  // ========================================================================

  Widget _buildSelection() {
    if (!widget.allowSelection) {
      return _buildDetails();
    }

    if (_activeGoats.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'This customer has no active goats available for checkout.',
            textAlign: TextAlign.center,
            style: AppTheme.body(size: 13),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        16,
        12,
        16,
        100,
      ),
      children: [
        Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: AppColors.headerGradient,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.pets,
                color: Colors.white,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select Goat(s)',
                      style: AppTheme.heading(
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Select one or more goats to check out.',
                      style: AppTheme.body(
                        size: 10,
                        color: Colors.white.withOpacity(.9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              'Active Goats',
              style: AppTheme.heading(size: 15),
            ),
            const Spacer(),
            if (_selectedIds.isNotEmpty)
              Text(
                '${_selectedIds.length} selected',
                style: AppTheme.body(
                  size: 11,
                  color: AppColors.darkGreen,
                  weight: FontWeight.w700,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        ..._activeGoats.map(
              (goat) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _selectionCard(goat),
          ),
        ),
      ],
    );
  }

  Widget _selectionCard(PalaiGoat goat) {
    final selected = _selectedIds.contains(goat.id);

    return InkWell(
      onTap: () => _toggleGoat(goat),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? AppColors.primaryGreen
                : AppColors.divider,
            width: selected ? 1.7 : 1,
          ),
        ),
        child: Row(
          children: [
            _goatImage(
              goat.beforeImage,
              size: 58,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Text(
                    goat.goatCode,
                    style: AppTheme.heading(size: 14),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${goat.breed} • ${goat.gender}',
                    style: AppTheme.body(size: 11),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${goat.weightAtCheckIn.toStringAsFixed(1)} kg at check-in',
                    style: AppTheme.body(
                      size: 10,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Checkbox(
              value: selected,
              activeColor: AppColors.primaryGreen,
              onChanged: (_) => _toggleGoat(goat),
            ),
          ],
        ),
      ),
    );
  }

  // ========================================================================
  // STEP 2 — DETAILS
  // ========================================================================

  Widget _buildDetails() {
    final goats = _selectedGoats;

    if (goats.isEmpty) {
      return Center(
        child: Text(
          'No goat selected.',
          style: AppTheme.body(),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        16,
        12,
        16,
        110,
      ),
      children: [
        _progressCard(goats.length),
        const SizedBox(height: 14),
        ...goats.asMap().entries.map(
              (entry) {
            final goat = entry.value;
            final data = _details[goat.id]!;

            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _goatDetailsCard(
                index: entry.key,
                goat: goat,
                data: data,
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _progressCard(int count) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: AppTheme.card(radius: 17),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: AppColors.lightGreen,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.fact_check_outlined,
              color: AppColors.darkGreen,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  '$count ${count == 1 ? 'goat' : 'goats'} selected',
                  style: AppTheme.heading(size: 14),
                ),
                const SizedBox(height: 3),
                Text(
                  'Enter the final details for each goat.',
                  style: AppTheme.body(size: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _goatDetailsCard({
    required int index,
    required PalaiGoat goat,
    required _GoatCheckoutData data,
  }) {
    final difference =
        data.finalWeight - goat.weightAtCheckIn;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: AppTheme.card(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _goatImage(
                goat.beforeImage,
                size: 58,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      goat.goatCode,
                      style: AppTheme.heading(size: 15),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${goat.breed} • ${goat.gender}',
                      style: AppTheme.body(size: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '#${index + 1}',
                  style: AppTheme.body(
                    size: 10,
                    color: AppColors.darkGreen,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 25),
          Text(
            'Final Weight',
            style: AppTheme.body(
              size: 11,
              weight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 7),
          TextField(
            controller: data.weightController,
            keyboardType:
            const TextInputType.numberWithOptions(
              decimal: true,
            ),
            onChanged: (value) {
              data.finalWeight =
                  double.tryParse(value) ?? 0;

              setState(() {});
            },
            decoration: const InputDecoration(
              hintText: 'Enter final weight',
              suffixText: 'kg',
              prefixIcon:
              Icon(Icons.monitor_weight_outlined),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _weightInfo(
                  'Check-In',
                  '${goat.weightAtCheckIn.toStringAsFixed(1)} kg',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _weightInfo(
                  'Change',
                  '${difference >= 0 ? '+' : ''}${difference.toStringAsFixed(1)} kg',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Health Status',
            style: AppTheme.body(
              size: 11,
              weight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 7),
          DropdownButtonFormField<String>(
            value: data.healthStatus,
            decoration: const InputDecoration(
              prefixIcon:
              Icon(Icons.health_and_safety_outlined),
            ),
            items: const [
              DropdownMenuItem(
                value: 'Healthy',
                child: Text('Healthy'),
              ),
              DropdownMenuItem(
                value: 'Under Observation',
                child: Text('Under Observation'),
              ),
              DropdownMenuItem(
                value: 'Sick',
                child: Text('Sick'),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;

              setState(() {
                data.healthStatus = value;
              });
            },
          ),
          const SizedBox(height: 16),
          Text(
            'After Palai Photo',
            style: AppTheme.body(
              size: 11,
              weight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _photoBox(
                  title: 'Before',
                  image: goat.beforeImage,
                  locked: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _photoBox(
                  title: 'After',
                  image: data.afterImage,
                  onTap: () => _pickAfterPhoto(data),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Delivery Status',
            style: AppTheme.body(
              size: 11,
              weight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 7),
          DropdownButtonFormField<String>(
            value: data.deliveryStatus,
            decoration: const InputDecoration(
              prefixIcon:
              Icon(Icons.local_shipping_outlined),
            ),
            items: const [
              DropdownMenuItem(
                value: 'Pending',
                child: Text('Pending'),
              ),
              DropdownMenuItem(
                value: 'Picked Up',
                child: Text('Picked Up'),
              ),
              DropdownMenuItem(
                value: 'Delivered',
                child: Text('Delivered'),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;

              setState(() {
                data.deliveryStatus = value;
              });
            },
          ),
          const SizedBox(height: 16),
          Text(
            'Notes',
            style: AppTheme.body(
              size: 11,
              weight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 7),
          TextField(
            controller: data.notesController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Add checkout notes...',
            ),
          ),
        ],
      ),
    );
  }

  Widget _weightInfo(
      String title,
      String value,
      ) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.paleGreen,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTheme.body(
              size: 8,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: AppTheme.body(
              size: 11,
              weight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ========================================================================
  // STEP 3 — REVIEW
  // ========================================================================

  Widget _buildReview() {
    final goats = _selectedGoats;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        16,
        12,
        16,
        110,
      ),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: AppColors.headerGradient,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.check_circle_outline,
                color: Colors.white,
                size: 30,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Checkout Review',
                      style: AppTheme.heading(
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${goats.length} ${goats.length == 1 ? 'goat' : 'goats'} ready',
                      style: AppTheme.body(
                        size: 10,
                        color: Colors.white.withOpacity(.9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ...goats.map(
              (goat) {
            final data = _details[goat.id]!;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _reviewCard(
                goat,
                data,
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _reviewCard(
      PalaiGoat goat,
      _GoatCheckoutData data,
      ) {
    final difference =
        data.finalWeight - goat.weightAtCheckIn;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(radius: 16),
      child: Column(
        children: [
          Row(
            children: [
              _goatImage(
                data.afterImage ?? goat.beforeImage,
                size: 56,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      goat.goatCode,
                      style: AppTheme.heading(size: 14),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${goat.breed} • ${goat.gender}',
                      style: AppTheme.body(size: 10),
                    ),
                  ],
                ),
              ),
              _statusChip(data.healthStatus),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              _reviewMetric(
                'Check-In',
                '${goat.weightAtCheckIn.toStringAsFixed(1)} kg',
              ),
              _reviewMetric(
                'Final',
                '${data.finalWeight.toStringAsFixed(1)} kg',
              ),
              _reviewMetric(
                'Change',
                '${difference >= 0 ? '+' : ''}${difference.toStringAsFixed(1)} kg',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.local_shipping_outlined,
                size: 16,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                data.deliveryStatus,
                style: AppTheme.body(size: 10),
              ),
              const Spacer(),
              if (data.afterImage != null)
                const Icon(
                  Icons.photo_camera,
                  color: AppColors.success,
                  size: 16,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    Color color;

    switch (status) {
      case 'Sick':
        color = AppColors.error;
        break;
      case 'Under Observation':
        color = AppColors.warning;
        break;
      default:
        color = AppColors.success;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status,
        style: AppTheme.body(
          size: 9,
          color: color,
          weight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _reviewMetric(
      String title,
      String value,
      ) {
    return Expanded(
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTheme.body(
              size: 8,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: AppTheme.body(
              size: 11,
              weight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ========================================================================
  // COMMON WIDGETS
  // ========================================================================

  Widget _photoBox({
    required String title,
    Uint8List? image,
    bool locked = false,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: locked ? null : onTap,
      child: Container(
        height: 150,
        decoration: BoxDecoration(
          color: AppColors.paleGreen,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.divider,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: image != null
            ? Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(
              image,
              fit: BoxFit.cover,
            ),
            Positioned(
              left: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.6),
                  borderRadius:
                  BorderRadius.circular(20),
                ),
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        )
            : Column(
          mainAxisAlignment:
          MainAxisAlignment.center,
          children: [
            Icon(
              locked
                  ? Icons.image_outlined
                  : Icons.add_a_photo_outlined,
              color: AppColors.primaryGreen,
              size: 28,
            ),
            const SizedBox(height: 7),
            Text(
              title,
              style: AppTheme.body(
                size: 10,
                color: AppColors.darkGreen,
                weight: FontWeight.w700,
              ),
            ),
            if (!locked)
              Text(
                'Tap to add',
                style: AppTheme.body(
                  size: 8,
                  color: AppColors.textMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _goatImage(
      Uint8List? image, {
        double size = 60,
      }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: image != null
          ? Image.memory(
        image,
        fit: BoxFit.cover,
      )
          : const Icon(
        Icons.pets,
        color: AppColors.primaryGreen,
        size: 28,
      ),
    );
  }

  Widget _buildBottomBar() {
    String label;

    if (_step == 0) {
      label = 'Continue';
    } else if (_step == 1) {
      label = 'Review Checkout';
    } else {
      label = 'Continue to Charges & Payment';
    }

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          16,
          10,
          16,
          12,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              blurRadius: 12,
              offset: Offset(0, -3),
              color: Color(0x18000000),
            ),
          ],
        ),
        child: Row(
          children: [
            if (_step > 0) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: _goBack,
                  style: OutlinedButton.styleFrom(
                    foregroundColor:
                    AppColors.darkGreen,
                    side: const BorderSide(
                      color: AppColors.divider,
                    ),
                    minimumSize:
                    const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                      BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 10),
            ],

            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: () async {
                  if (_step == 0) {
                    _continueFromSelection();
                    return;
                  }

                  if (_step == 1) {
                    _continueFromDetails();
                    return;
                  }

                  // -------------------------------------------------
                  // REVIEW -> CHARGES & PAYMENT
                  // -------------------------------------------------

                  final drafts =
                  _selectedGoats.map((goat) {
                    final data =
                    _details[goat.id]!;

                    return GoatCheckoutDraft(
                      goat: goat,
                      finalWeight:
                      data.finalWeight,
                      healthStatus:
                      data.healthStatus,
                      deliveryStatus:
                      data.deliveryStatus,
                      afterImage:
                      data.afterImage,
                      notes:
                      data.notesController
                          .text
                          .trim(),
                    );
                  }).toList();

                  if (_farmId == null) {
                    _showError(
                      'Farm information is not available. Please try again.',
                    );
                    return;
                  }

                  final result =
                  await Navigator.of(
                    context,
                  ).push(
                    fastRoute(
                      CheckoutChargesPaymentScreen(
                        farmId: _farmId!,
                        customerId: widget.customerId,
                        goats: drafts,
                      ),
                    ),
                  );

                  if (!mounted) return;

                  if (result == true) {
                    Navigator.of(
                      context,
                    ).pop(true);
                  }
                },

                style:
                ElevatedButton.styleFrom(
                  backgroundColor:
                  AppColors.primaryGreen,
                  foregroundColor:
                  Colors.white,
                  minimumSize:
                  const Size.fromHeight(
                    50,
                  ),
                  shape:
                  RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(
                      14,
                    ),
                  ),
                ),

                child: Text(
                  label,
                  textAlign:
                  TextAlign.center,
                  style:
                  const TextStyle(
                    fontWeight:
                    FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// LOCAL CHECKOUT DATA
// ============================================================================

class _GoatCheckoutData {
  final PalaiGoat goat;

  late final TextEditingController weightController;
  late final TextEditingController notesController;

  double finalWeight;
  String healthStatus;
  String deliveryStatus;

  Uint8List? afterImage;

  _GoatCheckoutData(this.goat)
      : finalWeight =
      goat.currentWeight ??
          goat.weightAtCheckIn,
        healthStatus = goat.healthStatus,
        deliveryStatus = 'Pending' {
    weightController = TextEditingController(
      text: finalWeight.toStringAsFixed(1),
    );

    notesController = TextEditingController(
      text: goat.notes,
    );
  }

  void dispose() {
    weightController.dispose();
    notesController.dispose();
  }
}