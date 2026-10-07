import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app_theme.dart';
import '../../../goat_icons.dart';
import '../../../models/goat_model.dart';
import '../../../services/image_service.dart';
import '../../../services/lot_goat_registration_service.dart';
import '../../../widgets/image_source_sheet.dart';

/// One card per goat with what is needed to recognise it when the customer
/// collects it: photo (camera / gallery) and weight for every goat, plus
/// breed, age, color and health.
///
/// "Same details for all goats" is ON by default: breed, age, color and
/// health are filled once at the top and each goat card only asks for its
/// photo and weight. Turn it OFF when the goats differ — every card then
/// gets its own breed, age, color and health, started from the shared
/// values so only the differences have to be changed.
///
/// The parent reads the result through the State:
/// [SaleGoatsFormState.validate] then [SaleGoatsFormState.buildSpecs].
class SaleGoatsForm extends StatefulWidget {
  final int count;

  /// Photos to start the cards with (e.g. photos uploaded while the goats
  /// were at the supplier), in order. Extra photos are ignored.
  final List<Uint8List> initialPhotos;

  const SaleGoatsForm({
    super.key,
    required this.count,
    this.initialPhotos = const [],
  });

  @override
  State<SaleGoatsForm> createState() => SaleGoatsFormState();
}

class _GoatEntry {
  final TextEditingController weight = TextEditingController();
  final TextEditingController breed = TextEditingController();
  final TextEditingController age = TextEditingController();
  final TextEditingController color = TextEditingController();
  String health = Goat.healthStatusValues.first;
  Uint8List? photo;
  String? photoType;

  void dispose() {
    weight.dispose();
    breed.dispose();
    age.dispose();
    color.dispose();
  }
}

class SaleGoatsFormState extends State<SaleGoatsForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final List<_GoatEntry> _goats = [];

  // Shared details (used while _sameForAll is on).
  final TextEditingController _breed = TextEditingController();
  final TextEditingController _age = TextEditingController();
  final TextEditingController _color = TextEditingController();
  String _health = Goat.healthStatusValues.first;

  bool _sameForAll = true;
  bool _submitted = false;
  int? _pickingFor;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < widget.count; i++) {
      final entry = _GoatEntry();
      if (i < widget.initialPhotos.length &&
          widget.initialPhotos[i].isNotEmpty) {
        entry.photo = widget.initialPhotos[i];
        entry.photoType = 'image/jpeg';
      }
      _goats.add(entry);
    }
  }

  @override
  void dispose() {
    for (final g in _goats) {
      g.dispose();
    }
    _breed.dispose();
    _age.dispose();
    _color.dispose();
    super.dispose();
  }

  // ===========================================================================
  // PUBLIC
  // ===========================================================================

  /// True when every card is complete. Shows what is missing otherwise.
  bool validate() {
    setState(() => _submitted = true);
    final fieldsOk = _formKey.currentState?.validate() ?? false;
    final photosOk = _goats.every((g) => g.photo != null);

    if (!photosOk && mounted) {
      final missing = [
        for (var i = 0; i < _goats.length; i++)
          if (_goats[i].photo == null) '${i + 1}',
      ].join(', ');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Add a photo for goat $missing.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
    return fieldsOk && photosOk;
  }

  List<SaleGoatSpec> buildSpecs() => [
    for (final g in _goats)
      SaleGoatSpec(
        breed: (_sameForAll ? _breed : g.breed).text.trim(),
        ageMonths:
        int.tryParse((_sameForAll ? _age : g.age).text.trim()) ?? 0,
        weight: double.tryParse(g.weight.text.trim()) ?? 0,
        color: (_sameForAll ? _color : g.color).text.trim(),
        healthStatus: _sameForAll ? _health : g.health,
        photo: g.photo,
        photoContentType: g.photoType,
      ),
  ];

  // ===========================================================================
  // ACTIONS
  // ===========================================================================

  /// Switching to per-goat details starts every card from the shared
  /// values, so only what differs has to be changed.
  void _setSameForAll(bool value) {
    setState(() {
      if (!value) {
        for (final g in _goats) {
          if (g.breed.text.trim().isEmpty) g.breed.text = _breed.text;
          if (g.age.text.trim().isEmpty) g.age.text = _age.text;
          if (g.color.text.trim().isEmpty) g.color.text = _color.text;
          g.health = _health;
        }
      }
      _sameForAll = value;
    });
  }

  Future<void> _pickPhoto(int index) async {
    if (_pickingFor != null) return;
    setState(() => _pickingFor = index);
    try {
      final picked = await showImageSourceSheet(context, isGoatPhoto: true);
      if (picked == null || !mounted) return;
      setState(() {
        _goats[index].photo = picked.bytes;
        _goats[index].photoType = picked.contentType;
      });
    } on ImageTooLargeException {
      _error('That photo is too large. Please choose another.');
    } catch (_) {
      _error('Could not add the photo. Please try again.');
    } finally {
      if (mounted) setState(() => _pickingFor = null);
    }
  }

  void _error(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  // ===========================================================================
  // VALIDATORS
  // ===========================================================================

  String? _needBreed(String? v) =>
      (v ?? '').trim().isEmpty ? 'Enter breed' : null;

  String? _needAge(String? v) {
    final n = int.tryParse((v ?? '').trim());
    return n == null || n <= 0 ? 'Enter age' : null;
  }

  String? _needWeight(String? v) {
    final n = double.tryParse((v ?? '').trim());
    return n == null || n <= 0 ? 'Enter weight' : null;
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sharedCard(),
          const SizedBox(height: 12),
          for (var i = 0; i < _goats.length; i++) ...[
            _goatCard(i),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  /// The switch, and — while it is on — the shared breed / age / color /
  /// health fields.
  Widget _sharedCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: AppTheme.card(radius: 16).copyWith(
        border: Border.all(
          color: _sameForAll
              ? AppColors.primaryGreen.withValues(alpha: 0.5)
              : AppColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Same details for all goats',
                        style: AppTheme.heading(size: 13.5)),
                    Text(
                      _sameForAll
                          ? 'Breed, age, color and health below apply to '
                          'every goat. Photo and weight are per goat.'
                          : 'Each goat has its own breed, age, color and '
                          'health.',
                      style: AppTheme.body(size: 10.5),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _sameForAll,
                activeColor: AppColors.primaryGreen,
                onChanged: _setSameForAll,
              ),
            ],
          ),
          if (_sameForAll) ...[
            const SizedBox(height: 10),
            _detailsFields(
              breed: _breed,
              age: _age,
              color: _color,
              health: _health,
              onHealth: (v) => setState(() => _health = v),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detailsFields({
    required TextEditingController breed,
    required TextEditingController age,
    required TextEditingController color,
    required String health,
    required ValueChanged<String> onHealth,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _field(breed, 'Breed', validator: _needBreed)),
            const SizedBox(width: 8),
            Expanded(
              child: _field(age, 'Age (months)',
                  digits: true, validator: _needAge),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _field(color, 'Color (optional)')),
            const SizedBox(width: 8),
            Expanded(child: _healthDropdown(health, onHealth)),
          ],
        ),
      ],
    );
  }

  Widget _goatCard(int i) {
    final g = _goats[i];
    final missingPhoto = _submitted && g.photo == null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.card(radius: 16).copyWith(
        border: Border.all(
          color: missingPhoto
              ? AppColors.error
              : AppColors.divider.withValues(alpha: 0.8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _photoBox(i, missingPhoto),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(GoatIcons.paw,
                            size: 14, color: AppColors.primaryGreen),
                        const SizedBox(width: 6),
                        Text('Goat ${i + 1}',
                            style: AppTheme.heading(size: 14)),
                        if (g.photo != null) ...[
                          const Spacer(),
                          GestureDetector(
                            onTap: () => _pickPhoto(i),
                            child: Text(
                              'Change photo',
                              style: AppTheme.body(
                                size: 11,
                                color: AppColors.darkGreen,
                                weight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    _field(
                      g.weight,
                      'Weight (kg)',
                      decimals: true,
                      validator: _needWeight,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!_sameForAll) ...[
            const SizedBox(height: 10),
            _detailsFields(
              breed: g.breed,
              age: g.age,
              color: g.color,
              health: g.health,
              onHealth: (v) => setState(() => g.health = v),
            ),
          ],
        ],
      ),
    );
  }

  Widget _photoBox(int i, bool missing) {
    final g = _goats[i];
    final borderColor = missing ? AppColors.error : AppColors.divider;

    return GestureDetector(
      onTap: () => _pickPhoto(i),
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          color: AppColors.primaryGreen.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: _pickingFor == i
            ? const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        )
            : g.photo != null
            ? Image.memory(g.photo!, fit: BoxFit.cover)
            : Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo_outlined,
                color: missing
                    ? AppColors.error
                    : AppColors.primaryGreen),
            const SizedBox(height: 4),
            Text(
              'Photo',
              style: AppTheme.body(
                size: 10.5,
                color:
                missing ? AppColors.error : AppColors.darkGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // FIELDS — with visible borders (the app theme hides input borders)
  // ===========================================================================

  OutlineInputBorder _border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: color, width: width),
      );

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    contentPadding:
    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: _border(AppColors.divider),
    enabledBorder: _border(AppColors.divider),
    focusedBorder: _border(AppColors.primaryGreen, 1.5),
    errorBorder: _border(AppColors.error),
    focusedErrorBorder: _border(AppColors.error, 1.5),
  );

  Widget _field(
      TextEditingController controller,
      String label, {
        bool digits = false,
        bool decimals = false,
        String? Function(String?)? validator,
      }) {
    return TextFormField(
      controller: controller,
      keyboardType: digits
          ? TextInputType.number
          : decimals
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      inputFormatters: digits
          ? [FilteringTextInputFormatter.digitsOnly]
          : decimals
          ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}'))]
          : null,
      textCapitalization: digits || decimals
          ? TextCapitalization.none
          : TextCapitalization.words,
      style: AppTheme.body(size: 13, color: AppColors.textDark),
      decoration: _decoration(label),
      validator: validator,
    );
  }

  Widget _healthDropdown(String value, ValueChanged<String> onChanged) {
    // A plain dropdown inside a decorator (not a FormField), so a changed
    // value always shows straight away.
    return InputDecorator(
      decoration: _decoration('Health'),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          isDense: true,
          style: AppTheme.body(size: 13, color: AppColors.textDark),
          items: [
            for (final h in Goat.healthStatusValues)
              DropdownMenuItem(value: h, child: Text(h)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}