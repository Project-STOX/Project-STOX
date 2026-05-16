class NotificationModel {
  final int? notificationId;
  final int senderId;
  final int recipientId;
  final String message;
  final String type;
  final DateTime? sentAt;

  NotificationModel({
    this.notificationId,
    required this.senderId,
    required this.recipientId,
    required this.message,
    required this.type,
    this.sentAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    DateTime? parseSentAt(dynamic raw) {
      if (raw == null) return null;
      if (raw is DateTime) return raw;
      if (raw is String) {
        return DateTime.tryParse(raw);
      }
      if (raw is int) {
        // Handle Unix timestamps in seconds or milliseconds.
        final milliseconds = raw > 1000000000000 ? raw : raw * 1000;
        return DateTime.fromMillisecondsSinceEpoch(milliseconds);
      }
      return null;
    }

    return NotificationModel(
      notificationId: (json['notification_id'] as num?)?.toInt(),
      senderId: (json['sender_id'] as num?)?.toInt() ?? 0,
      recipientId: (json['recipient_id'] as num?)?.toInt() ?? 0,
      message: json['message']?.toString() ?? '',
      type: json['type']?.toString() ?? 'Info',
      sentAt: parseSentAt(json['sent_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sender_id': senderId,
      'recipient_id': recipientId,
      'message': message,
      'type': type,
    };
  }
}
