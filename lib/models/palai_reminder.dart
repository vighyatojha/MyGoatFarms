import 'package:cloud_firestore/cloud_firestore.dart';

/// ============================================================================
/// PALAI REMINDER
/// ============================================================================
///
/// Central model for all Palai reminders.
///
/// IMPORTANT:
///
/// Reminder generation will be handled later by the Reminder Engine.
/// This model only represents the reminder itself.
///
/// Example:
///
/// Vaccination
///   Customer: C001
///   Goat: G001
///   Due: 25 Aug 2026
///
/// Hoof Cutting
///   Goat: G002
///   Due: 30 Aug 2026
///
/// Pending Payment
///   Customer: C003
///   Due: 05 Sep 2026
///
/// The same model can therefore power the entire reminder system.
///
/// ============================================================================

enum PalaiReminderType {
  vaccination,
  hoofCutting,
  hairTrimming,
  weightTracking,
  pendingPayment,
  healthAlert,
  medicine,
  monthlyPhoto,
  other,
}

enum PalaiReminderStatus {
  pending,
  completed,
  dismissed,
  cancelled,
  overdue,
}

enum PalaiReminderPriority {
  low,
  normal,
  high,
  urgent,
}

class PalaiReminder {
  // ==========================================================================
  // IDENTITY
  // ==========================================================================

  final String id;

  /// Customer related to this reminder.
  ///
  /// Empty when the reminder belongs only to Own Farm.
  final String customerId;

  /// Goat related to this reminder.
  final String goatId;

  // ==========================================================================
  // REMINDER INFORMATION
  // ==========================================================================

  final PalaiReminderType type;

  final PalaiReminderStatus status;

  final PalaiReminderPriority priority;

  /// Short title shown to the user.
  ///
  /// Example:
  /// "Vaccination Due"
  final String title;

  /// Human-friendly explanation.
  ///
  /// Example:
  /// "Rabies vaccination is due for this goat."
  final String message;

  // ==========================================================================
  // DATES
  // ==========================================================================

  /// Date/time on which the reminder becomes relevant.
  final DateTime dueDate;

  /// When the reminder was completed.
  final DateTime? completedAt;

  /// When the reminder was dismissed.
  final DateTime? dismissedAt;

  // ==========================================================================
  // RELATED RECORD
  // ==========================================================================

  /// ID of the related record.
  ///
  /// Examples:
  ///
  /// Vaccination record ID
  /// Hoof record ID
  /// Bill ID
  /// Health record ID
  final String relatedRecordId;

  // ==========================================================================
  // REMINDER SETTINGS
  // ==========================================================================

  /// Whether notification should be generated.
  final bool notificationEnabled;

  /// Number of days before due date when notification should start.
  final int reminderBeforeDays;

  // ==========================================================================
  // METADATA
  // ==========================================================================

  /// Extra information which does not deserve a dedicated field.
  final Map<String, dynamic> metadata;

  final DateTime createdAt;

  final DateTime updatedAt;

  // ==========================================================================
  // CONSTRUCTOR
  // ==========================================================================

  const PalaiReminder({
    required this.id,
    this.customerId = '',
    this.goatId = '',
    required this.type,
    this.status = PalaiReminderStatus.pending,
    this.priority = PalaiReminderPriority.normal,
    required this.title,
    this.message = '',
    required this.dueDate,
    this.completedAt,
    this.dismissedAt,
    this.relatedRecordId = '',
    this.notificationEnabled = true,
    this.reminderBeforeDays = 1,
    this.metadata = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  // ==========================================================================
  // CREATE
  // ==========================================================================

  factory PalaiReminder.create({
    required String id,
    String customerId = '',
    String goatId = '',
    required PalaiReminderType type,
    PalaiReminderStatus status =
        PalaiReminderStatus.pending,
    PalaiReminderPriority priority =
        PalaiReminderPriority.normal,
    required String title,
    String message = '',
    required DateTime dueDate,
    String relatedRecordId = '',
    bool notificationEnabled = true,
    int reminderBeforeDays = 1,
    Map<String, dynamic> metadata =
    const {},
  }) {
    final now = DateTime.now();

    return PalaiReminder(
      id: id,
      customerId: customerId,
      goatId: goatId,
      type: type,
      status: status,
      priority: priority,
      title: title,
      message: message,
      dueDate: dueDate,
      relatedRecordId: relatedRecordId,
      notificationEnabled:
      notificationEnabled,
      reminderBeforeDays:
      reminderBeforeDays < 0
          ? 0
          : reminderBeforeDays,
      metadata:
      Map<String, dynamic>.from(
        metadata,
      ),
      createdAt: now,
      updatedAt: now,
    );
  }

  // ==========================================================================
  // COPY WITH
  // ==========================================================================

  PalaiReminder copyWith({
    String? id,
    String? customerId,
    String? goatId,
    PalaiReminderType? type,
    PalaiReminderStatus? status,
    PalaiReminderPriority? priority,
    String? title,
    String? message,
    DateTime? dueDate,
    DateTime? completedAt,
    DateTime? dismissedAt,
    String? relatedRecordId,
    bool? notificationEnabled,
    int? reminderBeforeDays,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PalaiReminder(
      id: id ?? this.id,
      customerId:
      customerId ?? this.customerId,
      goatId:
      goatId ?? this.goatId,
      type:
      type ?? this.type,
      status:
      status ?? this.status,
      priority:
      priority ?? this.priority,
      title:
      title ?? this.title,
      message:
      message ?? this.message,
      dueDate:
      dueDate ?? this.dueDate,
      completedAt:
      completedAt ?? this.completedAt,
      dismissedAt:
      dismissedAt ?? this.dismissedAt,
      relatedRecordId:
      relatedRecordId ??
          this.relatedRecordId,
      notificationEnabled:
      notificationEnabled ??
          this.notificationEnabled,
      reminderBeforeDays:
      reminderBeforeDays ??
          this.reminderBeforeDays,
      metadata:
      metadata ??
          this.metadata,
      createdAt:
      createdAt ?? this.createdAt,
      updatedAt:
      updatedAt ?? this.updatedAt,
    );
  }

  // ==========================================================================
  // FIRESTORE -> MODEL
  // ==========================================================================

  factory PalaiReminder.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data =
        doc.data() ?? <String, dynamic>{};

    return PalaiReminder(
      id: doc.id,

      customerId:
      _stringValue(
        data['customerId'],
      ),

      goatId:
      _stringValue(
        data['goatId'],
      ),

      type:
      _typeValue(
        data['type'],
      ),

      status:
      _statusValue(
        data['status'],
      ),

      priority:
      _priorityValue(
        data['priority'],
      ),

      title:
      _stringValue(
        data['title'],
      ),

      message:
      _stringValue(
        data['message'],
      ),

      dueDate:
      _dateValue(
        data['dueDate'],
      ),

      completedAt:
      _nullableDateValue(
        data['completedAt'],
      ),

      dismissedAt:
      _nullableDateValue(
        data['dismissedAt'],
      ),

      relatedRecordId:
      _stringValue(
        data['relatedRecordId'],
      ),

      notificationEnabled:
      _boolValue(
        data['notificationEnabled'],
        fallback: true,
      ),

      reminderBeforeDays:
      _intValue(
        data['reminderBeforeDays'],
        fallback: 1,
      ),

      metadata:
      _mapValue(
        data['metadata'],
      ),

      createdAt:
      _dateValue(
        data['createdAt'],
      ),

      updatedAt:
      _dateValue(
        data['updatedAt'],
      ),
    );
  }

  // ==========================================================================
  // MODEL -> FIRESTORE
  // ==========================================================================

  Map<String, dynamic> toMap({
    bool useServerTimestamps = false,
  }) {
    return {
      'customerId': customerId,
      'goatId': goatId,
      'type': type.name,
      'status': status.name,
      'priority': priority.name,
      'title': title,
      'message': message,
      'dueDate':
      Timestamp.fromDate(dueDate),
      'completedAt':
      completedAt == null
          ? null
          : Timestamp.fromDate(
        completedAt!,
      ),
      'dismissedAt':
      dismissedAt == null
          ? null
          : Timestamp.fromDate(
        dismissedAt!,
      ),
      'relatedRecordId':
      relatedRecordId,
      'notificationEnabled':
      notificationEnabled,
      'reminderBeforeDays':
      reminderBeforeDays,
      'metadata': metadata,
      if (useServerTimestamps)
        'createdAt':
        FieldValue.serverTimestamp()
      else
        'createdAt':
        Timestamp.fromDate(
          createdAt,
        ),
      if (useServerTimestamps)
        'updatedAt':
        FieldValue.serverTimestamp()
      else
        'updatedAt':
        Timestamp.fromDate(
          updatedAt,
        ),
    };
  }

  // ==========================================================================
  // ACTIONS
  // ==========================================================================

  /// Marks the reminder as completed.
  PalaiReminder complete() {
    final now = DateTime.now();

    return copyWith(
      status:
      PalaiReminderStatus.completed,
      completedAt: now,
      updatedAt: now,
    );
  }

  /// Dismisses the reminder.
  PalaiReminder dismiss() {
    final now = DateTime.now();

    return copyWith(
      status:
      PalaiReminderStatus.dismissed,
      dismissedAt: now,
      updatedAt: now,
    );
  }

  /// Cancels the reminder.
  PalaiReminder cancel() {
    return copyWith(
      status:
      PalaiReminderStatus.cancelled,
      updatedAt: DateTime.now(),
    );
  }

  /// Marks the reminder as overdue.
  PalaiReminder markOverdue() {
    if (isCompleted ||
        isDismissed ||
        isCancelled) {
      return this;
    }

    return copyWith(
      status:
      PalaiReminderStatus.overdue,
      updatedAt: DateTime.now(),
    );
  }

  // ==========================================================================
  // STATUS HELPERS
  // ==========================================================================

  bool get isPending {
    return status ==
        PalaiReminderStatus.pending;
  }

  bool get isCompleted {
    return status ==
        PalaiReminderStatus.completed;
  }

  bool get isDismissed {
    return status ==
        PalaiReminderStatus.dismissed;
  }

  bool get isCancelled {
    return status ==
        PalaiReminderStatus.cancelled;
  }

  bool get isOverdue {
    return status ==
        PalaiReminderStatus.overdue;
  }

  bool get isActive {
    return isPending || isOverdue;
  }

  // ==========================================================================
  // PRIORITY HELPERS
  // ==========================================================================

  bool get isLowPriority {
    return priority ==
        PalaiReminderPriority.low;
  }

  bool get isNormalPriority {
    return priority ==
        PalaiReminderPriority.normal;
  }

  bool get isHighPriority {
    return priority ==
        PalaiReminderPriority.high;
  }

  bool get isUrgent {
    return priority ==
        PalaiReminderPriority.urgent;
  }

  // ==========================================================================
  // TYPE HELPERS
  // ==========================================================================

  bool get isVaccination {
    return type ==
        PalaiReminderType.vaccination;
  }

  bool get isHoofCutting {
    return type ==
        PalaiReminderType.hoofCutting;
  }

  bool get isHairTrimming {
    return type ==
        PalaiReminderType.hairTrimming;
  }

  bool get isWeightTracking {
    return type ==
        PalaiReminderType.weightTracking;
  }

  bool get isPendingPayment {
    return type ==
        PalaiReminderType.pendingPayment;
  }

  bool get isHealthAlert {
    return type ==
        PalaiReminderType.healthAlert;
  }

  bool get isMedicine {
    return type ==
        PalaiReminderType.medicine;
  }

  bool get isMonthlyPhoto {
    return type ==
        PalaiReminderType.monthlyPhoto;
  }

  // ==========================================================================
  // TYPE LABEL
  // ==========================================================================

  String get typeLabel {
    switch (type) {
      case PalaiReminderType.vaccination:
        return 'Vaccination';

      case PalaiReminderType.hoofCutting:
        return 'Hoof Cutting';

      case PalaiReminderType.hairTrimming:
        return 'Hair Trimming';

      case PalaiReminderType.weightTracking:
        return 'Weight Tracking';

      case PalaiReminderType.pendingPayment:
        return 'Pending Payment';

      case PalaiReminderType.healthAlert:
        return 'Health Alert';

      case PalaiReminderType.medicine:
        return 'Medicine';

      case PalaiReminderType.monthlyPhoto:
        return 'Monthly Photo';

      case PalaiReminderType.other:
        return 'Other';
    }
  }

  // ==========================================================================
  // STATUS LABEL
  // ==========================================================================

  String get statusLabel {
    switch (status) {
      case PalaiReminderStatus.pending:
        return 'Pending';

      case PalaiReminderStatus.completed:
        return 'Completed';

      case PalaiReminderStatus.dismissed:
        return 'Dismissed';

      case PalaiReminderStatus.cancelled:
        return 'Cancelled';

      case PalaiReminderStatus.overdue:
        return 'Overdue';
    }
  }

  // ==========================================================================
  // PRIORITY LABEL
  // ==========================================================================

  String get priorityLabel {
    switch (priority) {
      case PalaiReminderPriority.low:
        return 'Low';

      case PalaiReminderPriority.normal:
        return 'Normal';

      case PalaiReminderPriority.high:
        return 'High';

      case PalaiReminderPriority.urgent:
        return 'Urgent';
    }
  }

  // ==========================================================================
  // DATE HELPERS
  // ==========================================================================

  bool get isDueToday {
    final now = DateTime.now();

    return dueDate.year == now.year &&
        dueDate.month == now.month &&
        dueDate.day == now.day;
  }

  bool get isDueSoon {
    if (!isActive) {
      return false;
    }

    final today = _dateOnly(
      DateTime.now(),
    );

    final reminderDate =
    _dateOnly(dueDate);

    final difference =
        reminderDate
            .difference(today)
            .inDays;

    return difference >= 0 &&
        difference <=
            reminderBeforeDays;
  }

  int get daysUntilDue {
    final today = _dateOnly(
      DateTime.now(),
    );

    final reminderDate =
    _dateOnly(dueDate);

    return reminderDate
        .difference(today)
        .inDays;
  }

  int get daysOverdue {
    final days =
    -daysUntilDue;

    return days > 0 ? days : 0;
  }

  // ==========================================================================
  // VALIDATION
  // ==========================================================================

  String? validate() {
    if (title.trim().isEmpty) {
      return 'Reminder title is required.';
    }

    if (reminderBeforeDays < 0) {
      return 'Reminder days cannot be negative.';
    }

    if (isVaccination &&
        goatId.trim().isEmpty) {
      return 'Goat ID is required for vaccination reminders.';
    }

    if (isHoofCutting &&
        goatId.trim().isEmpty) {
      return 'Goat ID is required for hoof cutting reminders.';
    }

    if (isHairTrimming &&
        goatId.trim().isEmpty) {
      return 'Goat ID is required for hair trimming reminders.';
    }

    if (isPendingPayment &&
        customerId.trim().isEmpty) {
      return 'Customer ID is required for payment reminders.';
    }

    return null;
  }

  // ==========================================================================
  // FIRESTORE HELPERS
  // ==========================================================================

  static String _stringValue(
      dynamic value, {
        String fallback = '',
      }) {
    if (value == null) {
      return fallback;
    }

    final result =
    value.toString();

    if (result.trim().isEmpty) {
      return fallback;
    }

    return result;
  }

  static bool _boolValue(
      dynamic value, {
        required bool fallback,
      }) {
    if (value == null) {
      return fallback;
    }

    if (value is bool) {
      return value;
    }

    if (value is String) {
      return value.toLowerCase() ==
          'true';
    }

    return fallback;
  }

  static int _intValue(
      dynamic value, {
        required int fallback,
      }) {
    if (value == null) {
      return fallback;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
      value.toString(),
    ) ??
        fallback;
  }

  static Map<String, dynamic>
  _mapValue(
      dynamic value,
      ) {
    if (value
    is Map<String, dynamic>) {
      return Map<String, dynamic>.from(
        value,
      );
    }

    if (value is Map) {
      return Map<String, dynamic>.from(
        value,
      );
    }

    return <String, dynamic>{};
  }

  static DateTime _dateValue(
      dynamic value, {
        DateTime? fallback,
      }) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String) {
      return DateTime.tryParse(
        value,
      ) ??
          fallback ??
          DateTime.now();
    }

    return fallback ??
        DateTime.now();
  }

  static DateTime? _nullableDateValue(
      dynamic value,
      ) {
    if (value == null) {
      return null;
    }

    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String) {
      return DateTime.tryParse(
        value,
      );
    }

    return null;
  }

  static PalaiReminderType
  _typeValue(
      dynamic value,
      ) {
    switch (value?.toString()) {
      case 'vaccination':
        return PalaiReminderType.vaccination;

      case 'hoofCutting':
        return PalaiReminderType.hoofCutting;

      case 'hairTrimming':
        return PalaiReminderType.hairTrimming;

      case 'weightTracking':
        return PalaiReminderType.weightTracking;

      case 'pendingPayment':
        return PalaiReminderType.pendingPayment;

      case 'healthAlert':
        return PalaiReminderType.healthAlert;

      case 'medicine':
        return PalaiReminderType.medicine;

      case 'monthlyPhoto':
        return PalaiReminderType.monthlyPhoto;

      default:
        return PalaiReminderType.other;
    }
  }

  static PalaiReminderStatus
  _statusValue(
      dynamic value,
      ) {
    switch (value?.toString()) {
      case 'pending':
        return PalaiReminderStatus.pending;

      case 'completed':
        return PalaiReminderStatus.completed;

      case 'dismissed':
        return PalaiReminderStatus.dismissed;

      case 'cancelled':
        return PalaiReminderStatus.cancelled;

      case 'overdue':
        return PalaiReminderStatus.overdue;

      default:
        return PalaiReminderStatus.pending;
    }
  }

  static PalaiReminderPriority
  _priorityValue(
      dynamic value,
      ) {
    switch (value?.toString()) {
      case 'low':
        return PalaiReminderPriority.low;

      case 'normal':
        return PalaiReminderPriority.normal;

      case 'high':
        return PalaiReminderPriority.high;

      case 'urgent':
        return PalaiReminderPriority.urgent;

      default:
        return PalaiReminderPriority.normal;
    }
  }

  static DateTime _dateOnly(
      DateTime date,
      ) {
    return DateTime(
      date.year,
      date.month,
      date.day,
    );
  }

  // ==========================================================================
  // DEBUG
  // ==========================================================================

  @override
  String toString() {
    return 'PalaiReminder('
        'id: $id, '
        'type: ${type.name}, '
        'title: $title, '
        'dueDate: $dueDate, '
        'status: ${status.name}'
        ')';
  }
}