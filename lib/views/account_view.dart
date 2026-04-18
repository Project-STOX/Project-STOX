import 'package:flutter/material.dart';
import '../controllers/user_controller.dart';
import '../controllers/auth_controller.dart';
import '../models/user.dart';

class AccountView extends StatefulWidget {
  final UserModel user;
  final bool isEmbedded;
  final void Function(UserModel)? onUserUpdated;

  const AccountView({
    super.key,
    required this.user,
    this.isEmbedded = false,
    this.onUserUpdated,
  });

  @override
  State<AccountView> createState() => _AccountViewState();
}

class _AccountViewState extends State<AccountView> {
  final UserController _userController = UserController();
  final AuthController _authController = AuthController();
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _usernameController;
  late TextEditingController _emailController;

  bool _tfaActive = false;
  bool _isLoading = false;
  bool _useTfaForPasswordChange = false;
  bool _verifyEmailChange = true;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.user.username);
    _emailController = TextEditingController(text: widget.user.email);
    _tfaActive = widget.user.tfaActive;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final normalizedEmail = _emailController.text.trim().toLowerCase();
      final normalizedUsername = _usernameController.text.trim();
      final emailChanged = normalizedEmail != widget.user.email.trim().toLowerCase();
      final verifyEmailChange = emailChanged && _verifyEmailChange;

      final updatedUser = await _userController.updateUser(
        widget.user.userId,
        username: normalizedUsername,
        email: normalizedEmail,
        verifyEmailChange: verifyEmailChange,
        actorUserId: widget.user.userId,
      );

      if (mounted) {
        final message = verifyEmailChange
            ? 'Profile updated. Verify the new email address to finish the change.'
            : 'Profile updated successfully';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
        // If embedded, notify parent instead of popping the entire dashboard
        if (widget.isEmbedded) {
          widget.onUserUpdated?.call(updatedUser);
        } else {
          // Return updated user to the dashboard (sidebar mode)
          Navigator.of(context).pop(updatedUser);
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating profile: $e')),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.isEmbedded ? null : AppBar(title: const Text('Account Settings')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Profile Information',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value?.isEmpty ?? true) return 'Username is required';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      onChanged: (_) => setState(() {}),
                      validator: (value) {
                        if (value?.isEmpty ?? true) return 'Email is required';
                        if (!value!.contains('@')) return 'Invalid email format';
                        return null;
                      },
                    ),
                    if (_emailController.text.trim().toLowerCase() != widget.user.email.trim().toLowerCase()) ...[
                      const SizedBox(height: 16),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Verify email change'),
                        subtitle: const Text('Send a confirmation link to the new email address'),
                        value: _verifyEmailChange,
                        onChanged: (value) => setState(() => _verifyEmailChange = value),
                      ),
                    ],
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _saveProfile,
                      child: const Text('Save Profile'),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }
}