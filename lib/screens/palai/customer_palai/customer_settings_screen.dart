import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class CustomerSettingsScreen extends StatefulWidget {
  final String customerId;

  const CustomerSettingsScreen({
    super.key,
    required this.customerId,
  });

  @override
  State<CustomerSettingsScreen> createState() =>
      _CustomerSettingsScreenState();
}

class _CustomerSettingsScreenState
    extends State<CustomerSettingsScreen> {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  int _vaccinationReminderDays = 30;
  int _hoofCuttingReminderDays = 30;
  int _hairTrimmingReminderDays = 30;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  // ===========================================================================
  // LOAD SETTINGS
  // ===========================================================================

  Future<void> _loadSettings() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final document = await _firestore
          .collection('palaiCustomers')
          .doc(widget.customerId)
          .get();

      if (!mounted) {
        return;
      }

      if (!document.exists) {
        setState(() {
          _loading = false;
          _error = 'Customer not found.';
        });
        return;
      }

      final data = document.data() ?? {};

      final rawSettings = data['settings'];

      final settings = rawSettings is Map
          ? Map<String, dynamic>.from(rawSettings)
          : <String, dynamic>{};

      setState(() {
        _vaccinationReminderDays =
            _readInt(
              settings['vaccinationReminderDays'],
              30,
            );

        _hoofCuttingReminderDays =
            _readInt(
              settings['hoofCuttingReminderDays'],
              30,
            );

        _hairTrimmingReminderDays =
            _readInt(
              settings['hairTrimmingReminderDays'],
              30,
            );

        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error = 'Unable to load customer settings.';
      });
    }
  }

  // ===========================================================================
  // SAVE SETTINGS
  // ===========================================================================

  Future<void> _saveSettings() async {
    if (_saving) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      await _firestore
          .collection('palaiCustomers')
          .doc(widget.customerId)
          .set(
        {
          'settings': {
            'vaccinationReminderDays':
            _vaccinationReminderDays,
            'hoofCuttingReminderDays':
            _hoofCuttingReminderDays,
            'hairTrimmingReminderDays':
            _hairTrimmingReminderDays,
          },
          'updatedAt': Timestamp.now(),
        },
        SetOptions(merge: true),
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Customer settings saved.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to save settings. Please try again.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Customer Settings',
        ),
      ),
      body: _buildBody(),
      bottomNavigationBar:
      _loading || _error != null
          ? null
          : SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            16,
            10,
            16,
            16,
          ),
          child: SizedBox(
            height: 52,
            width: double.infinity,
            child: FilledButton.icon(
              onPressed:
              _saving
                  ? null
                  : _saveSettings,
              icon: _saving
                  ? const SizedBox(
                width: 20,
                height: 20,
                child:
                CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              )
                  : const Icon(
                Icons.save_outlined,
              ),
              label: Text(
                _saving
                    ? 'Saving...'
                    : 'Save Settings',
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return _buildError();
    }

    return RefreshIndicator(
      onRefresh: _loadSettings,
      child: ListView(
        physics:
        const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          16,
          16,
          16,
          110,
        ),
        children: [
          _buildIntroCard(),

          const SizedBox(height: 24),

          _buildSectionTitle(
            'Care Reminders',
          ),

          const SizedBox(height: 10),

          _buildReminderCard(
            icon: Icons.vaccines_outlined,
            title: 'Vaccination',
            description:
            'Set how often vaccination reminders should be generated for this customer.',
            value:
            _vaccinationReminderDays,
            options: const [
              15,
              30,
              45,
              60,
              90,
            ],
            onChanged: (value) {
              setState(() {
                _vaccinationReminderDays =
                    value;
              });
            },
          ),

          const SizedBox(height: 12),

          _buildReminderCard(
            icon: Icons.content_cut_outlined,
            title: 'Hoof Cutting',
            description:
            'Choose the reminder interval for hoof cutting (khud cutting).',
            value:
            _hoofCuttingReminderDays,
            options: const [
              30,
              45,
            ],
            onChanged: (value) {
              setState(() {
                _hoofCuttingReminderDays =
                    value;
              });
            },
          ),

          const SizedBox(height: 12),

          _buildReminderCard(
            icon: Icons.content_cut_outlined,
            title: 'Hair Trimming',
            description:
            'Set how often hair trimming reminders should be generated.',
            value:
            _hairTrimmingReminderDays,
            options: const [
              15,
              30,
              45,
              60,
              90,
            ],
            onChanged: (value) {
              setState(() {
                _hairTrimmingReminderDays =
                    value;
              });
            },
          ),

          const SizedBox(height: 24),

          _buildSectionTitle(
            'How reminders work',
          ),

          const SizedBox(height: 10),

          _buildExplanationCard(),
        ],
      ),
    );
  }

  // ===========================================================================
  // INTRO CARD
  // ===========================================================================

  Widget _buildIntroCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 24,
              child: Icon(
                Icons
                    .notifications_active_outlined,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reminder Preferences',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                      fontWeight:
                      FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'These settings apply specifically to this customer. They will later be used by the Palai reminder system.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium,
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
  // REMINDER CARD
  // ===========================================================================

  Widget _buildReminderCard({
    required IconData icon,
    required String title,
    required String description,
    required int value,
    required List<int> options,
    required ValueChanged<int> onChanged,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  child: Icon(icon),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                          fontWeight:
                          FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            DropdownButtonFormField<int>(
              initialValue:
              options.contains(value)
                  ? value
                  : options.first,
              decoration:
              const InputDecoration(
                labelText: 'Reminder interval',
                prefixIcon: Icon(
                  Icons
                      .schedule_outlined,
                ),
                border:
                OutlineInputBorder(),
              ),
              items: options.map(
                    (days) {
                  return DropdownMenuItem<int>(
                    value: days,
                    child: Text(
                      'Every $days days',
                    ),
                  );
                },
              ).toList(),
              onChanged: (newValue) {
                if (newValue != null) {
                  onChanged(newValue);
                }
              },
            ),

            const SizedBox(height: 10),

            Container(
              width: double.infinity,
              padding:
              const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                borderRadius:
                BorderRadius.circular(10),
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Current setting: every $value days',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                        fontWeight:
                        FontWeight.w600,
                      ),
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
  // EXPLANATION
  // ===========================================================================

  Widget _buildExplanationCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildExplanationRow(
              icon:
              Icons.notifications_outlined,
              title: 'No automatic reminder yet',
              description:
              'For now, this screen only stores the customer preference.',
            ),
            const Divider(height: 24),
            _buildExplanationRow(
              icon:
              Icons.settings_outlined,
              title: 'Customer-specific settings',
              description:
              'Different customers can have different reminder intervals.',
            ),
            const Divider(height: 24),
            _buildExplanationRow(
              icon:
              Icons.auto_awesome_outlined,
              title: 'Reminder engine comes later',
              description:
              'The actual reminder generation will be connected during the Intelligence phase.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExplanationRow({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(
                  fontWeight:
                  FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // SECTION TITLE
  // ===========================================================================

  Widget _buildSectionTitle(
      String title,
      ) {
    return Text(
      title,
      style: Theme.of(context)
          .textTheme
          .titleLarge
          ?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    );
  }

  // ===========================================================================
  // ERROR
  // ===========================================================================

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              _error ??
                  'Something went wrong.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadSettings,
              icon: const Icon(
                Icons.refresh,
              ),
              label: const Text(
                'Retry',
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  int _readInt(
      dynamic value,
      int fallback,
      ) {
    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
      value?.toString() ?? '',
    ) ??
        fallback;
  }
}