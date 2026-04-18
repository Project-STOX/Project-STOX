import 'package:flutter/material.dart';
import '../controllers/role_controller.dart';
import '../controllers/user_controller.dart';
import '../models/role.dart';
import '../models/permission.dart';
import '../models/user.dart';
import '../controllers/notification_controller.dart';

class ManageRolesView extends StatefulWidget {
  final UserModel user;
  final bool isEmbedded;

  const ManageRolesView({super.key, required this.user, this.isEmbedded = false});

  @override
  _ManageRolesViewState createState() => _ManageRolesViewState();
}

class _ManageRolesViewState extends State<ManageRolesView> {
  final RoleController _roleController = RoleController();
  final UserController _userController = UserController();
  final NotificationController _notificationController =
      NotificationController();
  List<Role> _roles = [];
  List<Permission> _permissions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      await _roleController.ensurePermissionDictionary();
      final roles = await _roleController.getAllRoles();
      final permissions = await _roleController.getAllPermissions();
      setState(() {
        _roles = roles;
        _permissions = permissions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading data: $e')));
    }
  }

  Future<void> _addRole() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => RoleDialog(
        permissions: _permissions,
        roleController: _roleController,
      ),
    );
    if (result != null) {
      final roleId = await _roleController.createRole(
        result['name'],
        result['description'],
        actorUserId: widget.user.userId,
      );
      // Assign permissions
      for (final perm in result['permissions']) {
        await _roleController.assignPermissionToRole(
          roleId,
          perm.permId,
          actorUserId: widget.user.userId,
        );
      }
      _loadData();
    }
  }

  Future<void> _editRole(Role role) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => RoleDialog(
        role: role,
        permissions: _permissions,
        roleController: _roleController,
      ),
    );
    if (result != null) {
      await _roleController.updateRole(
        role.roleId,
        result['name'],
        result['description'],
        actorUserId: widget.user.userId,
      );
      // Update permissions
      final currentPerms = await _roleController.getPermissionsForRole(
        role.roleId,
      );
      final currentPermIds = currentPerms.map((p) => p.permId).toSet();
      final newPermIds = result['permissions'].map((p) => p.permId).toSet();

      if (currentPermIds.difference(newPermIds).isNotEmpty ||
          newPermIds.difference(currentPermIds).isNotEmpty) {
        // Find users in this role
        final roleUsers = await _roleController.getUsersForRole(role.roleId);
        final userIds = roleUsers.map((u) => u.userId).toList();

        // Actually update permissions in database
        // Remove permissions not in new set
        for (final permId in currentPermIds.difference(newPermIds)) {
          await _roleController.removePermissionFromRole(
            role.roleId,
            permId,
            actorUserId: widget.user.userId,
          );
        }
        // Add new permissions
        for (final permId in newPermIds.difference(currentPermIds)) {
          await _roleController.assignPermissionToRole(
            role.roleId,
            permId,
            actorUserId: widget.user.userId,
          );
        }

        if (userIds.isNotEmpty) {
          final addedPermNames = _permissions
              .where(
                (p) => newPermIds.difference(currentPermIds).contains(p.permId),
              )
              .map((p) => p.permName);
          final removedPermNames = _permissions
              .where(
                (p) => currentPermIds.difference(newPermIds).contains(p.permId),
              )
              .map((p) => p.permName);

          String message =
              'System: Access permissions for your role "${role.roleName}" have been updated.';
          if (addedPermNames.isNotEmpty) {
            message += '\nGranted: ${addedPermNames.join(', ')}';
          }
          if (removedPermNames.isNotEmpty) {
            message += '\nRevoked: ${removedPermNames.join(', ')}';
          }

          await _notificationController.sendNotifications(
            widget.user.userId, // The admin performing the update
            userIds.cast<int>(),
            message,
            'System',
          );
        }
      }

      _loadData();
    }
  }

  Future<void> _deleteRole(Role role) async {
    final hasUsers = await _roleController.roleHasUsers(role.roleId);
    if (hasUsers) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot delete role: it has assigned users'),
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Role'),
        content: Text('Are you sure you want to delete "${role.roleName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _roleController.deleteRole(
          role.roleId,
          actorUserId: widget.user.userId,
        );
        _loadData();
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error deleting role: $e')));
      }
    }
  }

  Future<void> _manageUsers(Role role) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RoleUsersView(
          role: role,
          roleController: _roleController,
          userController: _userController,
          adminUserId: widget.user.userId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.isEmbedded
          ? null
          : AppBar(title: const Text('Manage Roles & Permissions')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ElevatedButton(
                    onPressed: _addRole,
                    child: const Text('Add New Role'),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _roles.length,
                    itemBuilder: (context, index) {
                      final role = _roles[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 8.0,
                        ),
                        child: ListTile(
                          title: Text(role.roleName),
                          subtitle: Text(role.description ?? ''),
                          onTap: () => _manageUsers(role),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () => _editRole(role),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete),
                                onPressed: () => _deleteRole(role),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class RoleDialog extends StatefulWidget {
  final Role? role;
  final List<Permission> permissions;
  final RoleController roleController;

  const RoleDialog({
    super.key,
    this.role,
    required this.permissions,
    required this.roleController,
  });

  @override
  _RoleDialogState createState() => _RoleDialogState();
}

class _RoleDialogState extends State<RoleDialog> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  List<Permission> _selectedPermissions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    if (widget.role != null) {
      _nameController.text = widget.role!.roleName;
      _descriptionController.text = widget.role!.description ?? '';
      _loadPermissions();
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPermissions() async {
    try {
      final perms = await widget.roleController.getPermissionsForRole(
        widget.role!.roleId,
      );
      setState(() {
        _selectedPermissions = perms;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading permissions: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.role == null ? 'Add Role' : 'Edit Role'),
      content: _isLoading
          ? const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Role Name'),
                  ),
                  TextField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(labelText: 'Description'),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Permissions:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  ...widget.permissions.map((perm) {
                    final isSelected = _selectedPermissions.any(
                      (p) => p.permId == perm.permId,
                    );
                    return CheckboxListTile(
                      title: Text(perm.permName),
                      value: isSelected,
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _selectedPermissions.add(perm);
                          } else {
                            _selectedPermissions.removeWhere(
                              (p) => p.permId == perm.permId,
                            );
                          }
                        });
                      },
                    );
                  }),
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            if (_nameController.text.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Role name is required')),
              );
              return;
            }
            Navigator.pop(context, {
              'name': _nameController.text,
              'description': _descriptionController.text.isEmpty
                  ? null
                  : _descriptionController.text,
              'permissions': _selectedPermissions,
            });
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class RoleUsersView extends StatefulWidget {
  final Role role;
  final RoleController roleController;
  final UserController userController;
  final int adminUserId;

  const RoleUsersView({
    super.key,
    required this.role,
    required this.roleController,
    required this.userController,
    required this.adminUserId,
  });

  @override
  _RoleUsersViewState createState() => _RoleUsersViewState();
}

class _RoleUsersViewState extends State<RoleUsersView> {
  List<UserModel> _allUsers = [];
  List<UserModel> _roleUsers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final allUsers = await widget.userController.getAllUsers();
      final roleUsers = await widget.roleController.getUsersForRole(
        widget.role.roleId,
      );
      setState(() {
        _allUsers = allUsers;
        _roleUsers = roleUsers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading users: $e')));
    }
  }

  Future<void> _assignUser(UserModel user) async {
    try {
      await widget.roleController.assignUserToRole(
        user.userId,
        widget.role.roleId,
        actorUserId: widget.adminUserId,
      );
      _loadData();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error assigning user: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Manage Users for ${widget.role.roleName}')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Users in this role:',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _roleUsers.length,
                    itemBuilder: (context, index) {
                      final user = _roleUsers[index];
                      return ListTile(
                        title: Text(user.username),
                        subtitle: Text(user.email),
                      );
                    },
                  ),
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Add users to this role:',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _allUsers.length,
                    itemBuilder: (context, index) {
                      final user = _allUsers[index];
                      final isInRole = _roleUsers.any(
                        (u) => u.userId == user.userId,
                      );
                      return ListTile(
                        title: Text(user.username),
                        subtitle: Text(user.email),
                        trailing: isInRole
                            ? const Icon(Icons.check, color: Colors.green)
                            : IconButton(
                                icon: const Icon(Icons.add),
                                onPressed: () => _assignUser(user),
                              ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
