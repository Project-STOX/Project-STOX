// ignore_for_file: unnecessary_cast

import 'package:flutter/material.dart';
import '../controllers/user_controller.dart';
import '../controllers/auth_controller.dart';
import '../controllers/role_controller.dart';
import '../models/user.dart';
import '../models/role.dart';
import '../controllers/notification_controller.dart';

class ManageUsersView extends StatefulWidget {
  final UserModel user;

  const ManageUsersView({super.key, required this.user});

  @override
  State<ManageUsersView> createState() => _ManageUsersViewState();
}

class _ManageUsersViewState extends State<ManageUsersView> {
  final UserController _userController = UserController();
  final AuthController _authController = AuthController();
  final RoleController _roleController = RoleController();
  final NotificationController _notificationController = NotificationController();

  List<UserModel> _users = [];
  List<Role> _roles = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final users = await _userController.getAllUsers();
      final roles = await _userController.getAllRoles();
      setState(() {
        _users = users;
        _roles = roles;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    }
  }

  Future<void> _refreshData() async {
    await _loadData();
  }

  void _showUserDetails(UserModel user) {
    showDialog(
      context: context,
      builder: (context) => UserDetailsDialog(
        user: user,
        roles: _roles,
        onUpdate: _refreshData,
        userController: _userController,
        roleController: _roleController,
        adminId: widget.user.userId,
      ),
    );
  }

  void _showManageRolesDialog() {
    showDialog(
      context: context,
      builder: (context) => ManageRolesDialog(
        roles: _roles,
        onRolesUpdated: _refreshData,
        roleController: _roleController,
      ),
    );
  }

  void _showAddUserDialog() {
    showDialog(
      context: context,
      builder: (context) => AddUserDialog(
        roles: _roles,
        onUserAdded: _refreshData,
        userController: _userController,
        roleController: _roleController,
        adminId: widget.user.userId,
      ),
    );
  }

  Future<void> _deleteUser(UserModel user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete User'),
        content: Text('Are you sure you want to delete ${user.username}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _userController.deleteUser(
          user.userId,
          actorUserId: widget.user.userId,
        );
        await _refreshData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting user: $e')),
          );
        }
      }
    }
  }

  Future<void> _toggleUserActive(UserModel user) async {
    try {
      final newStatus = !user.isActive;
      await _userController.toggleUserActive(
        user.userId,
        newStatus,
        actorUserId: widget.user.userId,
      );
      
      // Send system notification to the user
      await _notificationController.sendNotifications(
        widget.user.userId, // The admin performing the action
        [user.userId],
        'System: Your account has been ${newStatus ? 'activated' : 'deactivated'} by the administrator.',
        'System',
      );

      await _refreshData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('User ${newStatus ? 'activated' : 'deactivated'} successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating user status: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Users'),
        actions: [
          FutureBuilder<bool>(
            future: _authController.hasPermission(widget.user.roleId, 'Manage Roles'),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data == true) {
                return IconButton(
                  icon: const Icon(Icons.admin_panel_settings),
                  onPressed: _showManageRolesDialog,
                  tooltip: 'Manage Roles',
                );
              }
              return const SizedBox.shrink();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshData,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddUserDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _users.isEmpty
              ? const Center(child: Text('No users found'))
              : ListView.builder(
                  itemCount: _users.length,
                  itemBuilder: (context, index) {
                    final user = _users[index];
                    final Role? role = _roles.cast<Role?>().firstWhere(
                      (r) => r?.roleId == user.roleId,
                      orElse: () => null,
                    );

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: user.isActive ? Colors.green : Colors.red,
                          child: Icon(
                            user.isActive ? Icons.check : Icons.check_circle,
                            color: Colors.white,
                          ),
                        ),
                        title: Text(user.username),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user.email),
                            Text('Role: ${role?.roleName ?? 'Unknown'}'),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                user.isActive ? Icons.block : Icons.check_circle,
                                color: user.isActive ? Colors.red : Colors.green,
                              ),
                              onPressed: () => _toggleUserActive(user),
                              tooltip: user.isActive ? 'Deactivate' : 'Activate',
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _showUserDetails(user),
                              tooltip: 'Edit User',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteUser(user),
                              tooltip: 'Delete User',
                            ),
                          ],
                        ),
                        onTap: () => _showUserDetails(user),
                      ),
                    );
                  },
                ),
    );
  }
}

class UserDetailsDialog extends StatefulWidget {
  final UserModel user;
  final List<Role> roles;
  final VoidCallback onUpdate;
  final UserController userController;
  final RoleController roleController;
  final NotificationController notificationController = NotificationController();
  final int adminId;

  UserDetailsDialog({
    super.key,
    required this.user,
    required this.roles,
    required this.onUpdate,
    required this.userController,
    required this.roleController,
    required this.adminId,
  });

  @override
  State<UserDetailsDialog> createState() => _UserDetailsDialogState();
}

class _UserDetailsDialogState extends State<UserDetailsDialog> {
  late TextEditingController _usernameController;
  late TextEditingController _emailController;
  late int _selectedRoleId;
  bool _isActive = false;
  bool _tfaActive = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.user.username);
    _emailController = TextEditingController(text: widget.user.email);
    _selectedRoleId = widget.user.roleId;
    _isActive = widget.user.isActive;
    _tfaActive = widget.user.tfaActive;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    setState(() => _isLoading = true);
    try {
      await widget.userController.updateUser(
        widget.user.userId,
        username: _usernameController.text,
        email: _emailController.text,
        roleId: _selectedRoleId,
        isActive: _isActive,
        tfaActive: _tfaActive,
        actorUserId: widget.adminId,
      );
      // Check for changes to notify
      if (widget.user.roleId != _selectedRoleId) {
        final newRole = widget.roles.firstWhere((r) => r.roleId == _selectedRoleId).roleName;
        await widget.notificationController.sendNotifications(
          widget.adminId,
          [widget.user.userId],
          'System: Your role has been changed to $newRole.',
          'System',
        );
      }
      if (widget.user.isActive != _isActive) {
        await widget.notificationController.sendNotifications(
          widget.adminId,
          [widget.user.userId],
          'System: Your account status has been changed to ${_isActive ? 'Active' : 'Inactive'}.',
          'System',
        );
      }

      widget.onUpdate();
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User updated successfully')),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating user: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('User Details - ${widget.user.username}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _selectedRoleId,
              decoration: const InputDecoration(labelText: 'Role'),
              items: widget.roles.map((role) {
                return DropdownMenuItem(
                  value: role.roleId,
                  child: Text(role.roleName),
                );
              }).toList(),
              onChanged: (value) => setState(() => _selectedRoleId = value!),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Active'),
              value: _isActive,
              onChanged: (value) => setState(() => _isActive = value),
            ),
            SwitchListTile(
              title: const Text('2FA Enabled'),
              value: _tfaActive,
              onChanged: (value) => setState(() => _tfaActive = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _saveChanges,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

class AddUserDialog extends StatefulWidget {
  final List<Role> roles;
  final VoidCallback onUserAdded;
  final UserController userController;
  final RoleController roleController;
  final int adminId;

  const AddUserDialog({
    super.key,
    required this.roles,
    required this.onUserAdded,
    required this.userController,
    required this.roleController,
    required this.adminId,
  });

  @override
  State<AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends State<AddUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  int? _selectedRoleId;
  bool _isLoading = false;
  bool _showPassword = false;
  bool _verifyEmail = false; // Default to false to avoid rate limits


  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _createUser() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await widget.userController.createUser(
        _usernameController.text,
        _emailController.text,
        _passwordController.text,
        _selectedRoleId!,
        verifyEmail: _verifyEmail,
        actorUserId: widget.adminId,
      );
      widget.onUserAdded();
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User created successfully')),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating user: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add New User'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: 'Username'),
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Username is required';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Email is required';
                  if (!value!.contains('@')) return 'Invalid email format';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                  ),
                ),
                obscureText: !_showPassword,
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Password is required';
                  if (value!.length < 6) return 'Password must be at least 6 characters';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: _selectedRoleId,
                decoration: const InputDecoration(labelText: 'Role'),
                items: widget.roles.map((role) {
                  return DropdownMenuItem(
                    value: role.roleId,
                    child: Text(role.roleName),
                  );
                }).toList(),
                validator: (value) {
                  if (value == null) return 'Please select a role';
                  return null;
                },
                onChanged: (value) => setState(() => _selectedRoleId = value),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Verify via Email'),
                subtitle: const Text('If off, user is created immediately without verification (avoids rate limits).'),
                value: _verifyEmail,
                onChanged: (value) => setState(() => _verifyEmail = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _createUser,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}

class ManageRolesDialog extends StatefulWidget {
  final List<Role> roles;
  final VoidCallback onRolesUpdated;
  final RoleController roleController;

  const ManageRolesDialog({
    super.key,
    required this.roles,
    required this.onRolesUpdated,
    required this.roleController,
  });

  @override
  State<ManageRolesDialog> createState() => _ManageRolesDialogState();
}

class _ManageRolesDialogState extends State<ManageRolesDialog> {
  late List<Role> _roles;

  @override
  void initState() {
    super.initState();
    _roles = List.from(widget.roles);
  }

  void _showAddRoleDialog() {
    showDialog(
      context: context,
      builder: (context) => AddRoleDialog(
        onRoleAdded: (role) {
          setState(() => _roles.add(role));
        },
        roleController: widget.roleController,
      ),
    );
  }

  void _showEditRoleDialog(Role role) {
    showDialog(
      context: context,
      builder: (context) => EditRoleDialog(
        role: role,
        onRoleUpdated: (updatedRole) {
          setState(() {
            final index = _roles.indexWhere((r) => r.roleId == updatedRole.roleId);
            if (index != -1) {
              _roles[index] = updatedRole;
            }
          });
        },
        roleController: widget.roleController,
      ),
    );
  }

  Future<void> _deleteRole(Role role) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Role'),
        content: Text('Are you sure you want to delete "${role.roleName}"? This may affect users assigned to this role.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await widget.roleController.deleteRole(role.roleId);
        setState(() {
          _roles.removeWhere((r) => r.roleId == role.roleId);
        });
        widget.onRolesUpdated();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Role deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting role: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Manage Roles'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Roles', style: TextStyle(fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _showAddRoleDialog,
                  tooltip: 'Add Role',
                ),
              ],
            ),
            const Divider(),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _roles.length,
                itemBuilder: (context, index) {
                  final role = _roles[index];
                  return ListTile(
                    title: Text(role.roleName),
                    subtitle: role.description != null ? Text(role.description!) : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _showEditRoleDialog(role),
                          tooltip: 'Edit Role',
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteRole(role),
                          tooltip: 'Delete Role',
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class AddRoleDialog extends StatefulWidget {
  final Function(Role) onRoleAdded;
  final RoleController roleController;

  const AddRoleDialog({
    super.key,
    required this.onRoleAdded,
    required this.roleController,
  });

  @override
  State<AddRoleDialog> createState() => _AddRoleDialogState();
}

class _AddRoleDialogState extends State<AddRoleDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _createRole() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await widget.roleController.createRole(
        _nameController.text,
        _descriptionController.text.isEmpty ? null : _descriptionController.text,
      );

      // Get the newly created role
      final roles = await widget.roleController.getAllRoles();
      final newRole = roles.lastWhere((r) => r.roleName == _nameController.text);

      widget.onRoleAdded(newRole);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Role created successfully')),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating role: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add New Role'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Role Name'),
              validator: (value) {
                if (value?.isEmpty ?? true) return 'Role name is required';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description (Optional)'),
              maxLines: 3,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _createRole,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}

class EditRoleDialog extends StatefulWidget {
  final Role role;
  final Function(Role) onRoleUpdated;
  final RoleController roleController;

  const EditRoleDialog({
    super.key,
    required this.role,
    required this.onRoleUpdated,
    required this.roleController,
  });

  @override
  State<EditRoleDialog> createState() => _EditRoleDialogState();
}

class _EditRoleDialogState extends State<EditRoleDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.role.roleName);
    _descriptionController = TextEditingController(text: widget.role.description ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _updateRole() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await widget.roleController.updateRole(
        widget.role.roleId,
        _nameController.text,
        _descriptionController.text.isEmpty ? null : _descriptionController.text,
      );

      final updatedRole = Role(
        roleId: widget.role.roleId,
        roleName: _nameController.text,
        description: _descriptionController.text.isEmpty ? null : _descriptionController.text,
      );

      widget.onRoleUpdated(updatedRole);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Role updated successfully')),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating role: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit Role - ${widget.role.roleName}'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Role Name'),
              validator: (value) {
                if (value?.isEmpty ?? true) return 'Role name is required';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description (Optional)'),
              maxLines: 3,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _updateRole,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Update'),
        ),
      ],
    );
  }
}
