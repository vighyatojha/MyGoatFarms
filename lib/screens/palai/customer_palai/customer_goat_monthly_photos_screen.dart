import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../models/palai_models.dart';
import '../../../services/image_service.dart';

class CustomerGoatMonthlyPhotosScreen extends StatefulWidget {
  final String customerId;
  final PalaiGoat goat;

  const CustomerGoatMonthlyPhotosScreen({
    super.key,
    required this.customerId,
    required this.goat,
  });

  @override
  State<CustomerGoatMonthlyPhotosScreen> createState() =>
      _CustomerGoatMonthlyPhotosScreenState();
}

class _CustomerGoatMonthlyPhotosScreenState
    extends State<CustomerGoatMonthlyPhotosScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _photosCollection {
    return _firestore
        .collection('palaiCustomers')
        .doc(widget.customerId)
        .collection('goats')
        .doc(widget.goat.id)
        .collection('monthlyPhotos');
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> get _photosStream {
    return _photosCollection
        .orderBy('month', descending: true)
        .snapshots();
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monthly Photos'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _photosStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildErrorState(snapshot.error);
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final photos = snapshot.data?.docs
              .map((doc) => MonthlyPhoto.fromDoc(doc))
              .where((photo) => photo.image.isNotEmpty)
              .toList() ??
              <MonthlyPhoto>[];

          return RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    100,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _buildGoatHeader(),
                      const SizedBox(height: 20),
                      _buildPhotoSummary(photos),
                      const SizedBox(height: 28),
                      _buildSectionHeader(photos),
                      const SizedBox(height: 12),
                      if (photos.isEmpty)
                        _buildEmptyState()
                      else
                        _buildMonthlyGroups(photos),
                    ]),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddPhotoOptions,
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Add Photo'),
      ),
    );
  }

  // ===========================================================================
  // GOAT HEADER
  // ===========================================================================

  Widget _buildGoatHeader() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: colors.primaryContainer,
              ),
              child: Icon(
                Icons.pets_outlined,
                size: 32,
                color: colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.goat.name.trim().isNotEmpty
                        ? widget.goat.name
                        : widget.goat.goatCode,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'ID: ${widget.goat.goatCode}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    widget.goat.breed.isEmpty
                        ? 'Breed not specified'
                        : widget.goat.breed,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Monthly growth & progress photos',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // SUMMARY
  // ===========================================================================

  Widget _buildPhotoSummary(List<MonthlyPhoto> photos) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final now = DateTime.now();

    final currentMonthPhotos = photos.where((photo) {
      return photo.month.year == now.year &&
          photo.month.month == now.month;
    }).length;

    final monthsCovered = photos
        .map(
          (photo) =>
      '${photo.month.year}-${photo.month.month}',
    )
        .toSet()
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Photo Summary',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _summaryCard(
                icon: Icons.photo_library_outlined,
                title: 'Total photos',
                value: photos.length.toString(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _summaryCard(
                icon: Icons.calendar_month_outlined,
                title: 'Months covered',
                value: monthsCovered.toString(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _summaryCard(
                icon: Icons.photo_camera_outlined,
                title: 'This month',
                value: currentMonthPhotos.toString(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _summaryCard(
                icon: Icons.timeline_outlined,
                title: 'Purpose',
                value: 'Growth',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _summaryCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.primaryContainer,
              ),
              child: Icon(
                icon,
                size: 21,
                color: colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // SECTION HEADER
  // ===========================================================================

  Widget _buildSectionHeader(List<MonthlyPhoto> photos) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Monthly History',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                photos.isEmpty
                    ? 'No photos added yet'
                    : 'Track how the goat changes month by month',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // MONTHLY GROUPS
  // ===========================================================================

  Widget _buildMonthlyGroups(List<MonthlyPhoto> photos) {
    final groups = <String, List<MonthlyPhoto>>{};

    for (final photo in photos) {
      final key =
          '${photo.month.year}-${photo.month.month.toString().padLeft(2, '0')}';

      groups.putIfAbsent(key, () => []).add(photo);
    }

    final sortedKeys = groups.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return Column(
      children: [
        for (final key in sortedKeys) ...[
          _buildMonthSection(
            groups[key]!,
          ),
          const SizedBox(height: 18),
        ],
      ],
    );
  }

  Widget _buildMonthSection(List<MonthlyPhoto> photos) {
    final first = photos.first;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          14,
          14,
          14,
          16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Theme.of(context)
                        .colorScheme
                        .primaryContainer,
                  ),
                  child: Icon(
                    Icons.calendar_month_outlined,
                    color: Theme.of(context)
                        .colorScheme
                        .onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _monthLabel(first.month),
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${photos.length} ${photos.length == 1 ? 'photo' : 'photos'}',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Add photo for this month',
                  onPressed: () => _showAddPhotoOptions(
                    initialMonth: first.month,
                  ),
                  icon: const Icon(
                    Icons.add_a_photo_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: photos.length,
              gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.88,
              ),
              itemBuilder: (context, index) {
                return _buildPhotoTile(photos[index]);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // PHOTO TILE
  // ===========================================================================

  Widget _buildPhotoTile(MonthlyPhoto photo) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openPhoto(photo),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(
              photo.image,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                  child: const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      size: 36,
                    ),
                  ),
                );
              },
            ),
            if (photo.weightKg != null)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${photo.weightKg!.toStringAsFixed(1)} kg',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(
                  10,
                  28,
                  10,
                  9,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black87,
                    ],
                  ),
                ),
                child: Text(
                  photo.notes.trim().isEmpty
                      ? _formatDate(photo.capturedAt)
                      : photo.notes,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // EMPTY STATE
  // ===========================================================================

  Widget _buildEmptyState() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          children: [
            Icon(
              Icons.photo_camera_back_outlined,
              size: 54,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              'No monthly photos yet',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              'Add one photo every month to create a simple visual growth history for this goat.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _showAddPhotoOptions,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Add First Photo'),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // ADD PHOTO OPTIONS
  // ===========================================================================

  Future<void> _showAddPhotoOptions({
    DateTime? initialMonth,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              20,
              8,
              20,
              24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Add Monthly Photo',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Choose how you want to take the goat photo.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 18),
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.camera_alt_outlined),
                  ),
                  title: const Text('Take Photo'),
                  subtitle: const Text(
                    'Use the phone camera',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _addPhoto(
                      fromCamera: true,
                      initialMonth: initialMonth,
                    );
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.photo_library_outlined),
                  ),
                  title: const Text('Choose from Gallery'),
                  subtitle: const Text(
                    'Select an existing photo',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _addPhoto(
                      fromCamera: false,
                      initialMonth: initialMonth,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ===========================================================================
  // PICK + SAVE PHOTO
  // ===========================================================================

  Future<void> _addPhoto({
    required bool fromCamera,
    DateTime? initialMonth,
  }) async {
    try {
      _showLoading();

      final PickedImage? picked;

      if (fromCamera) {
        picked = await ImageService.instance.pickFromCamera(
          maxStoredBytes: ImageService.goatPhotoMaxStoredBytes,
          maxDimension: ImageService.goatPhotoMaxDimension,
        );
      } else {
        picked = await ImageService.instance.pickFromGallery(
          maxStoredBytes: ImageService.goatPhotoMaxStoredBytes,
          maxDimension: ImageService.goatPhotoMaxDimension,
        );
      }

      if (!mounted) {
        return;
      }

      Navigator.of(context, rootNavigator: true).pop();

      if (picked == null) {
        return;
      }

      final result = await _showPhotoDetailsDialog(
        picked.bytes,
        initialMonth ?? DateTime.now(),
      );

      if (result == null || !mounted) {
        return;
      }

      await _savePhoto(
        bytes: picked.bytes,
        contentType: picked.contentType,
        month: result.month,
        notes: result.notes,
        weightKg: result.weightKg,
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        'Monthly photo saved successfully.',
      );
    } on ImageTooLargeException catch (error) {
      if (mounted) {
        _closeLoadingIfOpen();
        _showError(error.message);
      }
    } catch (error) {
      if (mounted) {
        _closeLoadingIfOpen();
        _showError(
          _friendlyError(error),
        );
      }
    }
  }

  // ===========================================================================
  // PHOTO DETAILS DIALOG
  // ===========================================================================

  Future<_PhotoDetailsResult?> _showPhotoDetailsDialog(
      Uint8List imageBytes,
      DateTime initialMonth,
      ) async {
    final notesController = TextEditingController();
    final weightController = TextEditingController();

    DateTime selectedMonth = DateTime(
      initialMonth.year,
      initialMonth.month,
      1,
    );

    final result = await showDialog<_PhotoDetailsResult>(
      context: context,
      builder: (dialogContext) {
        bool saving = false;
        String? weightError;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text(
                'Photo Details',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.memory(
                        imageBytes,
                        height: 210,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: saving
                          ? null
                          : () async {
                        final picked =
                        await showDatePicker(
                          context: context,
                          initialDate: selectedMonth,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                          helpText: 'Select photo month',
                        );

                        if (picked != null) {
                          setDialogState(() {
                            selectedMonth = DateTime(
                              picked.year,
                              picked.month,
                              1,
                            );
                          });
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Month',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(
                            Icons.calendar_month_outlined,
                          ),
                        ),
                        child: Text(
                          _monthLabel(selectedMonth),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: weightController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Weight (kg)',
                        hintText: 'e.g. 24.5',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(
                          Icons.monitor_weight_outlined,
                        ),
                        errorText: weightError,
                      ),
                      onChanged: (_) {
                        if (weightError != null) {
                          setDialogState(() {
                            weightError = null;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: notesController,
                      maxLines: 3,
                      textCapitalization:
                      TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Notes',
                        hintText:
                        'Optional: growth, appearance, health, etc.',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(
                          Icons.notes_outlined,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () {
                    final weight = double.tryParse(
                      weightController.text.trim(),
                    );

                    if (weight == null || weight <= 0) {
                      setDialogState(() {
                        weightError =
                        'Enter the goat\'s weight in kg';
                      });
                      return;
                    }

                    Navigator.pop(
                      dialogContext,
                      _PhotoDetailsResult(
                        month: selectedMonth,
                        notes: notesController.text.trim(),
                        weightKg: weight,
                      ),
                    );
                  },
                  child: const Text('Continue'),
                ),
              ],
            );
          },
        );
      },
    );

    notesController.dispose();
    weightController.dispose();

    return result;
  }

  // ===========================================================================
  // FIRESTORE SAVE
  // ===========================================================================

  Future<void> _savePhoto({
    required Uint8List bytes,
    required String contentType,
    required DateTime month,
    required String notes,
    required double weightKg,
  }) async {
    final reference = _photosCollection.doc();

    final photo = MonthlyPhoto(
      id: reference.id,
      month: DateTime(
        month.year,
        month.month,
        1,
      ),
      image: bytes,
      imageContentType: contentType,
      notes: notes,
      weightKg: weightKg,
      capturedAt: DateTime.now(),
    );

    await reference.set(
      photo.toMap(),
    );
  }

  // ===========================================================================
  // PHOTO VIEWER
  // ===========================================================================

  void _openPhoto(MonthlyPhoto photo) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(12),
          child: Stack(
            children: [
              InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.memory(
                    photo.image,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Row(
                  children: [
                    Container(
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        tooltip: 'Delete',
                        color: Colors.white,
                        onPressed: () async {
                          Navigator.pop(dialogContext);
                          await _confirmDelete(photo);
                        },
                        icon: const Icon(
                          Icons.delete_outline,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        tooltip: 'Close',
                        color: Colors.white,
                        onPressed: () {
                          Navigator.pop(dialogContext);
                        },
                        icon: const Icon(
                          Icons.close,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 14,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _monthLabel(photo.month),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      if (photo.weightKg != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Weight: ${photo.weightKg!.toStringAsFixed(1)} kg',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (photo.notes.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          photo.notes,
                          style: const TextStyle(
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ===========================================================================
  // DELETE
  // ===========================================================================

  Future<void> _confirmDelete(
      MonthlyPhoto photo,
      ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Delete Photo?',
          ),
          content: const Text(
            'This monthly photo will be permanently removed.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      _showLoading();

      await _photosCollection
          .doc(photo.id)
          .delete();

      if (!mounted) {
        return;
      }

      _closeLoadingIfOpen();

      _showMessage(
        'Photo deleted.',
      );
    } catch (error) {
      if (mounted) {
        _closeLoadingIfOpen();
        _showError(
          _friendlyError(error),
        );
      }
    }
  }

  // ===========================================================================
  // LOADING
  // ===========================================================================

  void _showLoading() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(22),
              child: CircularProgressIndicator(),
            ),
          ),
        );
      },
    );
  }

  void _closeLoadingIfOpen() {
    if (!mounted) {
      return;
    }

    Navigator.of(context, rootNavigator: true).pop();
  }

  // ===========================================================================
  // REFRESH
  // ===========================================================================

  Future<void> _refresh() async {
    await Future<void>.delayed(
      const Duration(milliseconds: 300),
    );
  }

  // ===========================================================================
  // ERROR HANDLING
  // ===========================================================================

  String _friendlyError(Object? error) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'You do not have permission to save monthly photos.';

        case 'unavailable':
          return 'Firebase is temporarily unavailable. Please check your internet connection.';

        case 'network-request-failed':
          return 'Network error. Please check your internet connection.';

        case 'resource-exhausted':
          return 'The photo could not be saved because the database size limit was reached.';
      }
    }

    return 'Something went wrong. Please try again.';
  }

  // ===========================================================================
  // FEEDBACK
  // ===========================================================================

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
  }

  // ===========================================================================
  // ERROR SCREEN
  // ===========================================================================

  Widget _buildErrorState(Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              'Unable to load monthly photos',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _friendlyError(error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                setState(() {});
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // FORMATTERS
  // ===========================================================================

  String _monthLabel(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    if (date.month < 1 || date.month > 12) {
      return '${date.year}';
    }

    return '${months[date.month - 1]} ${date.year}';
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');

    return '$day/$month/${date.year}';
  }
}

// ==============================================================================
// PHOTO DETAILS RESULT
// ==============================================================================

class _PhotoDetailsResult {
  final DateTime month;
  final String notes;
  final double weightKg;

  const _PhotoDetailsResult({
    required this.month,
    required this.notes,
    required this.weightKg,
  });
}