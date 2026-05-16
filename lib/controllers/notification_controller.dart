import '../services/api/api_client.dart';
import '../services/api/api_config.dart';
import '../models/notification.dart';
import '../models/user.dart';

class NotificationController {
  NotificationController({ApiClient? apiClient})
      : _api = apiClient ?? ApiClient(baseUrl: ApiConfig.baseUrl);

  final ApiClient _api;

  // Get notifications for a user
  Future<List<NotificationModel>> getNotificationsForUser(int userId) async {
    final response = await _api.get('/notifications/me', authorized: true);
    if (response is List) {
      return response
          .whereType<Map<String, dynamic>>()
          .map((json) => NotificationModel.fromJson(json))
          .toList();
    }
    return [];
  }

  // Get notifications with sender name
  Future<List<Map<String, dynamic>>> getNotificationsWithSender(int userId) async {
    final response = await _api.get('/notifications/me', authorized: true);
    if (response is List) {
      return response.whereType<Map<String, dynamic>>().toList();
    }
    return [];
  }

  // Send notifications to multiple users
  Future<void> sendNotifications(int senderId, List<int> recipientIds, String message, String type) async {
    if (recipientIds.isEmpty) return;
    await _api.post(
      '/notifications/send',
      body: {
        'recipient_ids': recipientIds,
        'message': message,
        'type': type,
      },
      authorized: true,
    );
  }

  // Get all users (for recipient selection)
  Future<List<UserModel>> getAllUsers() async {
    final response = await _api.get('/notifications/recipients', authorized: true);
    if (response is List) {
      return response
          .whereType<Map<String, dynamic>>()
          .map((json) => UserModel.fromJson(json))
          .toList();
    }
    return [];
  }

  // Ensure "Send message" permission exists in the database
  Future<void> ensureSendMessagePermission() async {
    return;
  }
}
