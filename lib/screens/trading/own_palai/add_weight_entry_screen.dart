import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';
import '../../../models/trading_goat_weight_entry.dart';
import '../../../services/firestore_service.dart';
import '../../../services/goat_service.dart';
import '../../../services/image_service.dart';
import '../../../widgets/image_source_sheet.dart';

class AddWeightEntryScreen extends StatefulWidget {
  final String farmId;
  final String goatId;

  const AddWeightEntryScreen({
    super.key,
    required this.farmId,
    required this.goatId,
  });

  @override
  State<AddWeightEntryScreen> createState() =>
      _AddWeightEntryScreenState();
}

class _AddWeightEntryScreenState extends State<AddWeightEntryScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _weightController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime _date = DateTime.now();

  Uint8List? _photoBytes;
  String? _photoContentType;

  bool _saving = false;

  late final AnimationController _skeletonController;

  @override
  void initState() {
    super.initState();

    _skeletonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
  }

  @override
  void dispose() {
    _skeletonController.dispose();
    _weightController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // SNACKBAR
  // ---------------------------------------------------------------------------

  void _showSnack(
      String message, {
        bool isError = false,
      }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
        isError ? AppColors.error : AppColors.darkGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PHOTO
  // ---------------------------------------------------------------------------

  Future<void> _pickPhoto() async {
    try {
      final picked = await showImageSourceSheet(
        context,
        isGoatPhoto: true,
      );

      if (picked == null || !mounted) return;

      setState(() {
        _photoBytes = picked.bytes;
        _photoContentType = picked.contentType;
      });
    } on ImageTooLargeException catch (e) {
      _showSnack(
        e.message,
        isError: true,
      );
    } catch (_) {
      _showSnack(
        'Could not add photo. Please try again.',
        isError: true,
      );
    }
  }

  void _removePhoto() {
    setState(() {
      _photoBytes = null;
      _photoContentType = null;
    });
  }

  // ---------------------------------------------------------------------------
  // DATE
  // ---------------------------------------------------------------------------

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: AppColors.stockTeal,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _date = picked;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // SAVE
  // ---------------------------------------------------------------------------

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final weight = double.tryParse(
      _weightController.text.trim(),
    );

    if (weight == null || weight <= 0) {
      _showSnack(
        'Enter a valid weight.',
        isError: true,
      );
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _saving = true;
    });

    _skeletonController.repeat(reverse: true);

    try {
      await GoatService.instance.addWeightEntry(
        farmId: widget.farmId,
        goatId: widget.goatId,
        entry: GoatWeightEntry(
          id: '',
          weight: weight,
          date: _date,
          photo: _photoBytes,
          photoContentType: _photoContentType,
          notes: _notesController.text.trim(),
        ),
      );

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      _showSnack(
        FirestoreService.instance.describeError(e),
        isError: true,
      );
    } finally {
      _skeletonController.stop();

      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        titleSpacing: 20,
        title: Text(
          'Log Weight Entry',
          style: AppTheme.heading(size: 18),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            16,
            5,
            16,
            24,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPhotoCard(),

                const SizedBox(height: 12),

                _buildWeightCard(),

                const SizedBox(height: 10),

                _buildDateCard(),

                const SizedBox(height: 10),

                _buildNotesCard(),

                const SizedBox(height: 16),

                _buildSaveButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PHOTO CARD
  // ---------------------------------------------------------------------------

  Widget _buildPhotoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 13,
      ),
      decoration: AppTheme.card(radius: 15),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.stockTeal.withOpacity(0.09),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.camera_alt_outlined,
              size: 17,
              color: AppColors.stockTeal,
            ),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Monthly Photo',
                  style: AppTheme.heading(size: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  _photoBytes == null
                      ? 'Optional photo for this weight check'
                      : 'Photo added',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(
                    size: 10.5,
                    color: AppColors.textGrey,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 10),

          // IMPORTANT:
          // This is intentionally a fixed-size compact widget.
          // It replaces PhotoUploadCircle because that widget can have
          // internal content larger than its parent constraints.
          _CompactPhotoPicker(
            imageBytes: _photoBytes,
            onTap: _saving ? null : _pickPhoto,
            onRemove: _saving ? null : _removePhoto,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // WEIGHT CARD
  // ---------------------------------------------------------------------------

  Widget _buildWeightCard() {
    return _formCard(
      title: 'Weight',
      icon: Icons.monitor_weight_outlined,
      color: AppColors.stockTeal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _textField(
              _weightController,
              hint: 'e.g. 24.5',
              keyboardType:
              const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (value) {
                final weight = double.tryParse(
                  (value ?? '').trim(),
                );

                if (weight == null || weight <= 0) {
                  return 'Enter a valid weight';
                }

                return null;
              },
            ),
          ),

          const SizedBox(width: 8),

          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(
              horizontal: 13,
            ),
            decoration: BoxDecoration(
              color: AppColors.stockTeal.withOpacity(0.08),
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: Text(
              'kg',
              style: AppTheme.heading(size: 12).copyWith(
                color: AppColors.stockTeal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // DATE CARD
  // ---------------------------------------------------------------------------

  Widget _buildDateCard() {
    return _formCard(
      title: 'Weight Check Date',
      icon: Icons.calendar_today_outlined,
      color: AppColors.tradingBlue,
      child: InkWell(
        onTap: _saving ? null : _pickDate,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: AppColors.tradingBlue.withOpacity(0.07),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.event_outlined,
                size: 17,
                color: AppColors.tradingBlue,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  DateFormat('dd MMM yyyy').format(_date),
                  style: AppTheme.body(
                    size: 12.5,
                    color: AppColors.textDark,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down,
                size: 18,
                color: AppColors.textGrey,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // NOTES CARD
  // ---------------------------------------------------------------------------

  Widget _buildNotesCard() {
    return _formCard(
      title: 'Notes',
      icon: Icons.notes_outlined,
      color: AppColors.warning,
      child: _textField(
        _notesController,
        hint: 'Optional notes about this weight check',
        maxLines: 3,
        optional: true,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SAVE BUTTON
  // ---------------------------------------------------------------------------

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: _saving ? null : _save,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.stockTeal,
          disabledBackgroundColor:
          AppColors.stockTeal.withOpacity(0.55),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _saving
            ? AnimatedBuilder(
          animation: _skeletonController,
          builder: (context, child) {
            return Opacity(
              opacity:
              0.45 +
                  (_skeletonController.value * 0.4),
              child: Container(
                width: 92,
                height: 13,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                  BorderRadius.circular(7),
                ),
              ),
            );
          },
        )
            : const Row(
          mainAxisAlignment:
          MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 18,
            ),
            SizedBox(width: 7),
            Text(
              'Save Weight Entry',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SHARED FORM CARD
  // ---------------------------------------------------------------------------

  Widget _formCard({
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: AppTheme.card(radius: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.09),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  icon,
                  size: 16,
                  color: color,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: AppTheme.heading(size: 13),
              ),
            ],
          ),

          const SizedBox(height: 9),

          child,
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TEXT FIELD
  // ---------------------------------------------------------------------------

  Widget _textField(
      TextEditingController controller, {
        String? hint,
        TextInputType? keyboardType,
        int maxLines = 1,
        bool optional = false,
        String? Function(String?)? validator,
      }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      enabled: !_saving,
      validator: validator ??
              (value) {
            if (!optional &&
                (value == null ||
                    value.trim().isEmpty)) {
              return 'Required';
            }

            return null;
          },
      style: AppTheme.body(
        size: 12.5,
        color: AppColors.textDark,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTheme.body(
          size: 11.5,
          color: AppColors.textGrey,
        ),
        filled: true,
        fillColor:
        AppColors.paleGreen.withOpacity(0.55),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(
            color: AppColors.divider.withOpacity(0.6),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(
            color: AppColors.stockTeal,
            width: 1.2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(
            color: AppColors.error,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(
            color: AppColors.error,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
    );
  }
}

// ============================================================================
// COMPACT PHOTO PICKER
// ============================================================================

class _CompactPhotoPicker extends StatelessWidget {
  final Uint8List? imageBytes;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  const _CompactPhotoPicker({
    required this.imageBytes,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 54,
      height: 54,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(14),
              child: Ink(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: AppColors.stockTeal.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color:
                    AppColors.stockTeal.withOpacity(0.18),
                    width: 1,
                  ),
                ),
                child: imageBytes == null
                    ? const Icon(
                  Icons.add_a_photo_outlined,
                  color: AppColors.stockTeal,
                  size: 21,
                )
                    : ClipRRect(
                  borderRadius:
                  BorderRadius.circular(13),
                  child: Image.memory(
                    imageBytes!,
                    width: 54,
                    height: 54,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),

          if (imageBytes != null)
            Positioned(
              right: -4,
              top: -4,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white,
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 11,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}