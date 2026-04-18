import 'package:flutter/material.dart';
import '../controllers/notification_controller.dart';
import '../controllers/role_controller.dart';
import '../models/role.dart';
import '../models/user.dart';

class SendNotificationView extends StatefulWidget {
  final int senderId;
  final bool isEmbedded;

  const SendNotificationView({super.key, required this.senderId, this.isEmbedded = false});

  @override
  State<SendNotificationView> createState() => _SendNotificationViewState();
}

class _SendNotificationViewState extends State<SendNotificationView> {
  final NotificationController _notificationController =
      NotificationController();
  final RoleController _roleController = RoleController();
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  List<Role> _allRoles = [];
  List<UserModel> _allUsers = [];
  final List<int> _selectedRoleIds = [];
  final List<int> _selectedUserIds = [];
  String _selectedType = 'Message';
  bool _isLoading = true;

  final List<String> _types = [
    'Info',
    'Alert',
    'Reminder',
    'System',
    'Task',
    'Message',
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final roles = await _roleController.getAllRoles();
      final users = await _notificationController.getAllUsers();
      setState(() {
        _allRoles = roles;
        _allUsers = users;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading data: $e')));
      }
      setState(() => _isLoading = false);
    }
  }

  List<UserModel> get _filteredUsers {
    List<UserModel> users = _allUsers;
    if (_selectedRoleIds.isNotEmpty) {
      users = users.where((u) => _selectedRoleIds.contains(u.roleId)).toList();
    }
    
    final query = _searchController.text.toLowerCase();
    if (query.isNotEmpty) {
      users = users.where((u) => 
        u.username.toLowerCase().contains(query) || 
        u.email.toLowerCase().contains(query)
      ).toList();
    }
    return users;
  }

  void _send() async {
    if (_messageController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter a message')));
      return;
    }

    final recipients = _selectedUserIds.isNotEmpty
        ? _selectedUserIds
        : _filteredUsers.map((u) => u.userId).toList();

    if (recipients.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No recipients selected')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _notificationController.sendNotifications(
        widget.senderId,
        recipients,
        _messageController.text.trim(),
        _selectedType,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message sent successfully')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error sending message: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.isEmbedded ? null : AppBar(title: const Text('Send Message')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select Roles (Optional - filters user list)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Wrap(
                    spacing: 8.0,
                    children: _allRoles.map((role) {
                      final isSelected = _selectedRoleIds.contains(role.roleId);
                      return FilterChip(
                        label: Text(role.roleName),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _selectedRoleIds.add(role.roleId);
                            } else {
                              _selectedRoleIds.remove(role.roleId);
                            }
                            // Reset individual user selection when roles change to avoid confusion
                            _selectedUserIds.clear();
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const Divider(height: 32),
                  const Text(
                    'Select Users (Optional - defaults to all in selected roles)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Search users...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 200,
                    child: ListView.builder(
                      itemCount: _filteredUsers.length,
                      itemBuilder: (context, index) {
                        final user = _filteredUsers[index];
                        return CheckboxListTile(
                          title: Text(user.username),
                          subtitle: Text(user.email),
                          value: _selectedUserIds.contains(user.userId),
                          onChanged: (selected) {
                            setState(() {
                              if (selected == true) {
                                _selectedUserIds.add(user.userId);
                              } else {
                                _selectedUserIds.remove(user.userId);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                  const Divider(height: 32),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedType,
                    decoration: const InputDecoration(
                      labelText: 'Message Type',
                      border: OutlineInputBorder(),
                    ),
                    items: _types
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (val) => setState(() => _selectedType = val!),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _messageController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Message',
                      hintText: 'Type your message here...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _send,
                      child: const Text('SEND MESSAGE'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
