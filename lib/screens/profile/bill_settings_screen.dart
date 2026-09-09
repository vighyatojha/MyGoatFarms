import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/bill_settings_model.dart';
import '../../services/firestore_service.dart';

/// Dedicated Bill Details editor.
///
/// This is intentionally a full screen instead of a bottom sheet because the
/// structured Terms & Conditions and Important Notes editors need room to be
/// readable and usable on smaller phones.
class BillSettingsScreen extends StatefulWidget {
  final String farmId;
  final BillSettings initialSettings;

  const BillSettingsScreen({
    super.key,
    required this.farmId,
    required this.initialSettings,
  });

  @override
  State<BillSettingsScreen> createState() => _BillSettingsScreenState();
}

class _BillSettingsScreenState extends State<BillSettingsScreen> {
  late final TextEditingController _businessName;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _footer;
  late final TextEditingController _otherTermsTitle;
  late final TextEditingController _otherTermsText;
  late final TextEditingController _otherNoteTitle;
  late final TextEditingController _otherNoteText;

  late List<BillTermSection> _terms;
  late List<BillNoteSection> _notes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.initialSettings;

    _businessName = TextEditingController(text: s.businessName);
    _address = TextEditingController(text: s.address);
    _phone = TextEditingController(text: s.phone);
    _email = TextEditingController(
      text: s.email.trim().isNotEmpty
          ? s.email
          : (FirebaseAuth.instance.currentUser?.email ?? ''),
    );
    _footer = TextEditingController(text: s.footerNote);
    _otherTermsTitle = TextEditingController(text: s.otherTermsTitle);
    _otherTermsText = TextEditingController(text: s.otherTermsText);
    _otherNoteTitle = TextEditingController(text: s.otherNoteTitle);
    _otherNoteText = TextEditingController(text: s.otherNoteText);

    _terms = s.termsSections.isEmpty
        ? List<BillTermSection>.from(defaultBillTermSections)
        : s.termsSections.map((e) => e.copyWith()).toList();
    _notes = s.importantNotes.isEmpty
        ? List<BillNoteSection>.from(defaultBillNoteSections)
        : s.importantNotes.map((e) => e.copyWith()).toList();
  }

  @override
  void dispose() {
    _businessName.dispose();
    _address.dispose();
    _phone.dispose();
    _email.dispose();
    _footer.dispose();
    _otherTermsTitle.dispose();
    _otherTermsText.dispose();
    _otherNoteTitle.dispose();
    _otherNoteText.dispose();
    super.dispose();
  }

  void _applyPreset(String preset) {
    setState(() {
      if (preset == 'recommended') {
        _terms = defaultBillTermSections
            .map((s) => s.copyWith(
          enabled: s.id == 'animal-care' ||
              s.id == 'health-vaccination' ||
              s.id == 'payment-terms',
        ))
            .toList();
      } else if (preset == 'complete') {
        _terms = defaultBillTermSections
            .map((s) => s.copyWith(enabled: true))
            .toList();
      } else {
        _terms = defaultBillTermSections
            .map((s) => s.copyWith(enabled: false))
            .toList();
      }
    });
  }

  Future<void> _editTerm(int index) async {
    final current = _terms[index];
    final title = TextEditingController(text: current.title);
    final text = TextEditingController(text: current.text);

    final result = await _showEditorDialog(
      title: 'Edit ${current.title}',
      titleController: title,
      textController: text,
      textLabel: 'Terms & conditions',
    );

    title.dispose();
    text.dispose();

    if (result != null && mounted) {
      setState(() {
        _terms[index] = current.copyWith(
          title: result.$1,
          text: result.$2,
        );
      });
    }
  }

  Future<void> _editNote(int index) async {
    final current = _notes[index];
    final title = TextEditingController(text: current.title);
    final text = TextEditingController(text: current.text);

    final result = await _showEditorDialog(
      title: 'Edit ${current.title}',
      titleController: title,
      textController: text,
      textLabel: 'Note',
    );

    title.dispose();
    text.dispose();

    if (result != null && mounted) {
      setState(() {
        _notes[index] = current.copyWith(
          title: result.$1,
          text: result.$2,
        );
      });
    }
  }

  /// Shared dialog used for editing a title+text pair.
  ///
  /// IMPORTANT: We always unfocus any active text field, and then defer the
  /// dialog's Navigator.pop() to the *next frame* via addPostFrameCallback.
  /// unfocus() alone is not enough: it only marks the floating label's
  /// AnimatedDefaultTextStyle dirty, it doesn't flush it. If pop() runs
  /// synchronously right after, the dialog route can be torn down before
  /// the current BuildScope flushes that dirty widget, which is what was
  /// causing the "'_dependents.isEmpty': is not true" crash when saving
  /// Terms/Notes.
  Future<(String, String)?> _showEditorDialog({
    required String title,
    required TextEditingController titleController,
    required TextEditingController textController,
    required String textLabel,
  }) {
    return showDialog<(String, String)>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogField(titleController, 'Section title'),
              const SizedBox(height: 12),
              _dialogField(textController, textLabel, maxLines: 6),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              // Unfocus first so no TextField in this dialog still holds
              // focus while the route/element gets torn down. The pop
              // itself is deferred to the next frame via
              // addPostFrameCallback so the unfocus-triggered
              // AnimatedDefaultTextStyle rebuild (the floating label) is
              // flushed by the current BuildScope *before* the dialog
              // route's elements get torn down. Popping synchronously here
              // tore down the route mid-frame, ahead of that flush, which
              // is what produced the "'_dependents.isEmpty': is not true"
              // assertion.
              FocusManager.instance.primaryFocus?.unfocus();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              });
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
            ),
            onPressed: () {
              final t = titleController.text.trim();
              final body = textController.text.trim();
              if (t.isEmpty || body.isEmpty) return;

              // Same fix as Cancel: drop focus, then defer the pop to the
              // next frame so the floating-label animation teardown is
              // flushed before the dialog route disappears.
              FocusManager.instance.primaryFocus?.unfocus();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, (t, body));
                }
              });
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  Future<void> _addOtherTerms() async {
    // Use scratch controllers seeded from the persisted values so that
    // cancelling the dialog never leaves half-typed text behind in the
    // controllers that actually get saved.
    final title = TextEditingController(text: _otherTermsTitle.text);
    final text = TextEditingController(text: _otherTermsText.text);

    final result = await _showEditorDialog(
      title: _otherTermsTitle.text.trim().isEmpty
          ? 'Add Other Terms'
          : 'Edit Other Terms',
      titleController: title,
      textController: text,
      textLabel: 'Other terms',
    );

    title.dispose();
    text.dispose();

    if (result != null && mounted) {
      setState(() {
        _otherTermsTitle.text = result.$1;
        _otherTermsText.text = result.$2;
      });
    }
  }

  Future<void> _addOtherNote() async {
    final title = TextEditingController(text: _otherNoteTitle.text);
    final text = TextEditingController(text: _otherNoteText.text);

    final result = await _showEditorDialog(
      title: _otherNoteTitle.text.trim().isEmpty
          ? 'Add Other Note'
          : 'Edit Other Note',
      titleController: title,
      textController: text,
      textLabel: 'Important note',
    );

    title.dispose();
    text.dispose();

    if (result != null && mounted) {
      setState(() {
        _otherNoteTitle.text = result.$1;
        _otherNoteText.text = result.$2;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;

    // Also make sure nothing on the main form still holds focus before we
    // start popping/showing snackbars after the async save completes.
    FocusManager.instance.primaryFocus?.unfocus();

    final businessName = _businessName.text.trim();
    if (businessName.isEmpty) {
      _showError('Business name cannot be empty.');
      return;
    }

    final phone = _phone.text.trim();
    final email = _email.text.trim();
    if (phone.isNotEmpty && !RegExp(r'^[0-9+\-\s()]{7,20}$').hasMatch(phone)) {
      _showError('Please enter a valid phone number.');
      return;
    }

    if (email.isNotEmpty &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      _showError('Please enter a valid email address.');
      return;
    }

    setState(() => _saving = true);

    final settings = BillSettings(
      businessName: businessName,
      address: _address.text.trim(),
      phone: phone,
      email: email,
      // Logo/photo is managed separately. Preserve the existing value.
      billLogo: widget.initialSettings.billLogo,
      billLogoContentType: widget.initialSettings.billLogoContentType,
      footerNote: _footer.text.trim().isEmpty
          ? 'Thank you for trusting us with your goat.'
          : _footer.text.trim(),
      // Preserve legacy values so an older installed build does not unexpectedly
      // erase them. The new UI simply never exposes them.
      tagline: widget.initialSettings.tagline,
      upiId: widget.initialSettings.upiId,
      terms: widget.initialSettings.terms,
      termsSections: _terms,
      otherTermsTitle: _otherTermsTitle.text.trim(),
      otherTermsText: _otherTermsText.text.trim(),
      otherTermsEnabled:
      _otherTermsTitle.text.trim().isNotEmpty &&
          _otherTermsText.text.trim().isNotEmpty,
      importantNotes: _notes,
      otherNoteTitle: _otherNoteTitle.text.trim(),
      otherNoteText: _otherNoteText.text.trim(),
      otherNoteEnabled:
      _otherNoteTitle.text.trim().isNotEmpty &&
          _otherNoteText.text.trim().isNotEmpty,
    );

    try {
      await FirestoreService.instance.updateBillSettings(
        widget.farmId,
        settings,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bill details updated'),
          backgroundColor: AppColors.primaryGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
      // Defer the pop to the next frame. The SnackBar's own entrance
      // animation and the earlier unfocus() both dirty
      // AnimatedDefaultTextStyle widgets (the SnackBar's text style and any
      // floating field labels). Popping this route synchronously right
      // after showSnackBar() tears the route down before that frame's
      // rebuilds are flushed by the current BuildScope, which is what
      // caused the "'_dependents.isEmpty': is not true" crash on save.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(settings);
      });
    } catch (e) {
      if (mounted) _showError(FirestoreService.instance.describeError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
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
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      appBar: AppBar(
        backgroundColor: AppColors.paleGreen,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        titleSpacing: 4,
        title: Text('Bill Details', style: AppTheme.heading(size: 18)),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 18),
              child: Center(
                child: SizedBox(
                  width: 19,
                  height: 19,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: SizedBox(
          height: 54,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text(
              'Save Bill Details',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _heroCard(),
            const SizedBox(height: 16),
            _section(
              title: 'Bill Header',
              icon: Icons.receipt_long_outlined,
              child: Column(
                children: [
                  _field(
                    _businessName,
                    label: 'Business / Farm name',
                    hint: 'e.g. Kamal\'s Farm',
                    icon: Icons.storefront_outlined,
                  ),
                  const SizedBox(height: 12),
                  _field(
                    _address,
                    label: 'Address',
                    hint: 'Farm address shown in the bill header',
                    icon: Icons.location_on_outlined,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  _field(
                    _phone,
                    label: 'Contact number',
                    hint: '+91 90000 00000',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  _field(
                    _email,
                    label: 'Email address',
                    hint: 'farm@example.com',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _section(
              title: 'Bill Footer',
              icon: Icons.favorite_border,
              child: _field(
                _footer,
                label: 'Thank-you note',
                hint: 'Thank you for trusting us with your goat.',
                icon: Icons.favorite_border,
                maxLines: 2,
              ),
            ),
            const SizedBox(height: 16),
            _termsSection(),
            const SizedBox(height: 16),
            _notesSection(),
            const SizedBox(height: 12),
            _infoBanner(),
          ],
        ),
      ),
    );
  }

  Widget _heroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: AppColors.headerGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.16),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: Colors.white.withOpacity(.25)),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: Colors.white,
              size: 29,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Customize your bill PDF',
                  style: AppTheme.heading(size: 16, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  'Only bill identity, header, footer, terms and notes are configured here. Progress and payment details come from their own screens.',
                  style: AppTheme.body(
                    size: 11,
                    color: Colors.white.withOpacity(.86),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _termsSection() {
    final enabledCount = _terms.where((e) => e.enabled).length;
    return _section(
      title: 'Terms & Conditions',
      icon: Icons.gavel_outlined,
      trailing: Text(
        '$enabledCount selected',
        style: AppTheme.body(size: 11, color: AppColors.primaryGreen, weight: FontWeight.w700),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose a ready-made set, then enable, disable or edit individual sections.',
            style: AppTheme.body(size: 11, color: AppColors.textGrey),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _presetChip('Recommended', 'recommended'),
              _presetChip('Complete', 'complete'),
              _presetChip('Start empty', 'empty'),
            ],
          ),
          const SizedBox(height: 14),
          ..._terms.asMap().entries.map(
                (entry) => _termTile(entry.key, entry.value),
          ),
          const SizedBox(height: 8),
          _customAction(
            icon: Icons.add_circle_outline,
            title: _otherTermsTitle.text.trim().isEmpty
                ? 'Add Other Terms'
                : _otherTermsTitle.text.trim(),
            subtitle: _otherTermsText.text.trim().isEmpty
                ? 'Add your own custom clause or farm policy'
                : _otherTermsText.text.trim(),
            onTap: _addOtherTerms,
          ),
          if (_otherTermsText.text.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      _otherTermsTitle.clear();
                      _otherTermsText.clear();
                    });
                  },
                  child: const Text('Remove other terms'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _notesSection() {
    final enabledCount = _notes.where((e) => e.enabled).length;
    return _section(
      title: 'Important Notes',
      icon: Icons.info_outline,
      trailing: Text(
        '$enabledCount selected',
        style: AppTheme.body(size: 11, color: AppColors.primaryGreen, weight: FontWeight.w700),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Keep short operational reminders separate from your legal terms.',
            style: AppTheme.body(size: 11, color: AppColors.textGrey),
          ),
          const SizedBox(height: 12),
          ..._notes.asMap().entries.map(
                (entry) => _noteTile(entry.key, entry.value),
          ),
          const SizedBox(height: 8),
          _customAction(
            icon: Icons.add_circle_outline,
            title: _otherNoteTitle.text.trim().isEmpty
                ? 'Add Other Note'
                : _otherNoteTitle.text.trim(),
            subtitle: _otherNoteText.text.trim().isEmpty
                ? 'Add another note that should appear on the bill'
                : _otherNoteText.text.trim(),
            onTap: _addOtherNote,
          ),
        ],
      ),
    );
  }

  Widget _termTile(int index, BillTermSection section) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      decoration: BoxDecoration(
        color: section.enabled ? const Color(0xFFF7FBF8) : const Color(0xFFF5F6F5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: section.enabled ? AppColors.lightGreen : const Color(0xFFE0E4E1),
        ),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 10, right: 8),
            leading: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: section.enabled
                    ? AppColors.primaryGreen
                    : const Color(0xFFDCE2DE),
                shape: BoxShape.circle,
              ),
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: section.enabled ? Colors.white : AppColors.textGrey,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
            title: Text(
              section.title,
              style: AppTheme.heading(size: 13),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                section.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body(size: 10, color: AppColors.textGrey),
              ),
            ),
            trailing: Switch.adaptive(
              value: section.enabled,
              activeColor: AppColors.primaryGreen,
              onChanged: (value) {
                setState(() {
                  _terms[index] = section.copyWith(enabled: value);
                });
              },
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _editTerm(index),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit text'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryGreen,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noteTile(int index, BillNoteSection section) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      decoration: BoxDecoration(
        color: section.enabled ? const Color(0xFFF7FBF8) : const Color(0xFFF5F6F5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: section.enabled ? AppColors.lightGreen : const Color(0xFFE0E4E1),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 12, right: 8),
        leading: Icon(
          Icons.check_circle_outline,
          color: section.enabled ? AppColors.primaryGreen : AppColors.textGrey,
        ),
        title: Text(section.title, style: AppTheme.heading(size: 13)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            section.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.body(size: 10, color: AppColors.textGrey),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Edit note',
              onPressed: () => _editNote(index),
              icon: const Icon(Icons.edit_outlined, size: 18),
            ),
            Switch.adaptive(
              value: section.enabled,
              activeColor: AppColors.primaryGreen,
              onChanged: (value) {
                setState(() {
                  _notes[index] = section.copyWith(enabled: value);
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _presetChip(String label, String value) {
    return ActionChip(
      label: Text(label),
      avatar: const Icon(Icons.auto_awesome_outlined, size: 15),
      onPressed: () => _applyPreset(value),
      side: const BorderSide(color: AppColors.lightGreen),
      backgroundColor: Colors.white,
      labelStyle: AppTheme.body(
        size: 11,
        color: AppColors.primaryGreen,
        weight: FontWeight.w700,
      ),
    );
  }

  Widget _customAction({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.lightGreen),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primaryGreen),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTheme.heading(size: 12)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(size: 10, color: AppColors.textGrey),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _infoBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.lightGreen.withOpacity(.45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: AppColors.primaryGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This screen controls presentation content only. Goat progress/report data and payment calculations are intentionally not duplicated here.',
              style: AppTheme.body(size: 11, color: AppColors.darkGreen),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primaryGreen, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: AppTheme.heading(size: 15))),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _field(
      TextEditingController controller, {
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
        prefixIcon: Icon(icon, color: AppColors.primaryGreen),
        filled: true,
        fillColor: const Color(0xFFF8FAF8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE2E9E3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primaryGreen, width: 1.2),
        ),
      ),
    );
  }

  Widget _dialogField(
      TextEditingController controller,
      String label, {
        int maxLines = 1,
      }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFF7F9F7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}