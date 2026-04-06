import '../services/supabase_service.dart';
import '../services/audit_log_service.dart';
import '../models/notification.dart';
import '../models/user.dart';

class NotificationController {
  final supabase = SupabaseService.client;
  final AuditLogService auditLogService = AuditLogService();

  // Get notifications for a user
  Future<List<NotificationModel>> getNotificationsForUser(int userId) async {
    try {
      final response = await supabase
          .from('notification')
          .select()
          .eq('recipient_id', userId)
          .order('sent_at', ascending: false);

      return (response as List).map((json) => NotificationModel.fromJson(json)).toList();
    } catch (e) {
      print('Error fetching notifications: $e');
      return [];
    }
  }

  // Get notifications with sender name
  Future<List<Map<String, dynamic>>> getNotificationsWithSender(int userId) async {
    try {
      final response = await supabase
          .from('notification')
          .select('*, sender:user!sender_id(username)')
          .eq('recipient_id', userId)
          .order('sent_at', ascending: false);

      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('Error fetching notifications with sender: $e');
      return [];
    }
  }

  // Send notifications to multiple users
  Future<void> sendNotifications(int senderId, List<int> recipientIds, String message, String type) async {
    if (recipientIds.isEmpty) return;

    final notifications = recipientIds.map((id) => {
      'sender_id': senderId,
      'recipient_id': id,
      'message': message,
      'type': type,
    }).toList();

    await supabase.from('notification').insert(notifications);

    await auditLogService.logAction(
      userId: senderId,
      action: 'Send notification',
      entityType: 'Notification',
      details:
          'Sent $type message to ${recipientIds.length} recipient(s).',
    );
  }

  // Get all users (for recipient selection)
  Future<List<UserModel>> getAllUsers() async {
    final response = await supabase
        .from('user')
        .select()
        .order('username');
    
    return (response as List).map((json) => UserModel.fromJson(json)).toList();
  }

  // Ensure "Send message" permission exists in the database
  Future<void> ensureSendMessagePermission() async {
    try {
      final perm = await supabase
          .from('permission')
          .select()
          .eq('perm_name', 'Send message')
          .maybeSingle();
      
      if (perm == null) {
        await supabase.from('permission').insert({
          'perm_id': 1,
          'perm_name': 'Send message'
        });
      }
    } catch (e) {
      print('Error ensuring permission exists: $e');
    }
  }
}
