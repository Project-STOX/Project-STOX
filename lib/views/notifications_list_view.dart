import 'package:flutter/material.dart';
import '../controllers/notification_controller.dart';
import 'package:intl/intl.dart';

class NotificationsListView extends StatefulWidget {
  final int userId;

  const NotificationsListView({super.key, required this.userId});

  @override
  State<NotificationsListView> createState() => _NotificationsListViewState();
}

class _NotificationsListViewState extends State<NotificationsListView> {
  final NotificationController _notificationController = NotificationController();
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
  }

  Future<void> _fetchNotifications() async {
    setState(() => _isLoading = true);
    try {
      final res = await _notificationController.getNotificationsWithSender(widget.userId);
      setState(() {
        _notifications = res;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading notifications: $e')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'Info': return Colors.blue;
      case 'Alert': return Colors.red;
      case 'Reminder': return Colors.yellow[700]!;
      case 'System': return Colors.grey;
      case 'Task': return Colors.lightBlue;
      case 'Message': return Colors.lightGreen;
      default: return Colors.blueGrey;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'Info': return Icons.info;
      case 'Alert': return Icons.error;
      case 'Reminder': return Icons.notifications_active;
      case 'System': return Icons.settings;
      case 'Task': return Icons.check_circle;
      case 'Message': return Icons.message;
      default: return Icons.notifications;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchNotifications,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? const Center(child: Text('No notifications found'))
              : ListView.builder(
                  itemCount: _notifications.length,
                  itemBuilder: (context, index) {
                    final note = _notifications[index];
                    final String sender = note['sender']?['username'] ?? 'System';
                    final DateTime? sentAt = note['sent_at'] != null ? DateTime.parse(note['sent_at']) : null;
                    final String type = note['type'] ?? 'Message';
                    
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _getTypeColor(type),
                          child: Icon(_getTypeIcon(type), color: Colors.white),
                        ),
                        title: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(sender, style: const TextStyle(fontWeight: FontWeight.bold)),
                            if (sentAt != null)
                              Text(
                                DateFormat('MMM d, HH:mm').format(sentAt),
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4.0),
                              child: Text(note['message'] ?? ''),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _getTypeColor(type).withAlpha(40),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                type,
                                style: TextStyle(fontSize: 10, color: _getTypeColor(type), fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
