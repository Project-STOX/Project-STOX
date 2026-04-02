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
    return NotificationModel(
      notificationId: json['notification_id'],
      senderId: json['sender_id'],
      recipientId: json['recipient_id'],
      message: json['message'] ?? '',
      type: json['type'] ?? 'Info',
      sentAt: json['sent_at'] != null ? DateTime.parse(json['sent_at']) : null,
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
