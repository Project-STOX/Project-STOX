import '../services/supabase_service.dart';
import '../models/notification.dart';
import '../models/user.dart';

class NotificationController {
  final supabase = SupabaseService.client;

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
      final lowercasePerm = await supabase
          .from('permission')
          .select()
          .eq('perm_name', 'Send message')
          .maybeSingle();
      
      final capitalPerm = await supabase
          .from('permission')
          .select()
          .eq('perm_name', 'Send Message')
          .maybeSingle();

      final typoPerm = await supabase
          .from('permission')
          .select()
          .eq('perm_name', 'Send mesage')
          .maybeSingle();

      if (lowercasePerm == null) {
        if (capitalPerm != null) {
          // Rename capital to lowercase if lowercase doesn't exist
          await supabase
              .from('permission')
              .update({'perm_name': 'Send message'})
              .eq('perm_id', capitalPerm['perm_id']);
        } else if (typoPerm != null) {
          // Rename typo to lowercase
          await supabase
              .from('permission')
              .update({'perm_name': 'Send message'})
              .eq('perm_id', typoPerm['perm_id']);
        } else {
          // Create new lowercase if nothing exists
          await supabase.from('permission').insert({'perm_name': 'Send message'});
        }
      } else {
        // Clean up duplicates if lowercase already exists
        if (capitalPerm != null) {
          // First, check if any roles are using the capital version and move them to the lowercase version if not already present
          final mappings = await supabase
              .from('role_permission')
              .select()
              .eq('perm_id', capitalPerm['perm_id']);
          
          for (final mapping in mappings) {
            final exists = await supabase
                .from('role_permission')
                .select()
                .eq('role_id', mapping['role_id'])
                .eq('perm_id', lowercasePerm['perm_id'])
                .maybeSingle();
            
            if (exists == null) {
              await supabase.from('role_permission').insert({
                'role_id': mapping['role_id'],
                'perm_id': lowercasePerm['perm_id']
              });
            }
            // Delete the old mapping
            await supabase
                .from('role_permission')
                .delete()
                .eq('role_id', mapping['role_id'])
                .eq('perm_id', capitalPerm['perm_id']);
          }

          // Delete the capital version from permission table
          await supabase
              .from('permission')
              .delete()
              .eq('perm_id', capitalPerm['perm_id']);
        }
        
        // Clean up typo if lowercase already exists
        if (typoPerm != null) {
            await supabase
                .from('permission')
                .delete()
                .eq('perm_id', typoPerm['perm_id']);
        }
      }
    } catch (e) {
      print('Error ensuring permission exists: $e');
    }
  }
}
