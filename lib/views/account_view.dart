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
  final _passwordFormKey = GlobalKey<FormState>();

  late TextEditingController _usernameController;
  late TextEditingController _emailController;
  late TextEditingController _oldPasswordController;
  late TextEditingController _newPasswordController;
  late TextEditingController _confirmPasswordController;
  late TextEditingController _tfaCodeController;

  bool _tfaActive = false;
  bool _isLoading = false;
  bool _useTfaForPasswordChange = false;
  bool _verifyEmailChange = true;
  bool _isOldPasswordVisible = false;
  bool _isNewPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.user.username);
    _emailController = TextEditingController(text: widget.user.email);
    _oldPasswordController = TextEditingController();
    _newPasswordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
    _tfaCodeController = TextEditingController();
    _tfaActive = widget.user.tfaActive;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _tfaCodeController.dispose();
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
        tfaActive: _tfaActive,
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

  Future<void> _changePassword() async {
    if (!_passwordFormKey.currentState!.validate()) return;

    if (_newPasswordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New passwords do not match')),
      );
      return;
    }

    if (_newPasswordController.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be at least 6 characters')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _userController.updatePassword(
        widget.user.userId,
        _oldPasswordController.text,
        _newPasswordController.text,
        tfaCode: _useTfaForPasswordChange ? _tfaCodeController.text : null,
        actorUserId: widget.user.userId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password changed successfully')),
        );
        _oldPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        _tfaCodeController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error changing password: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _sendTfaCode() async {
    try {
      await _authController.generate2FA(widget.user.userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('2FA code sent to your email')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending 2FA code: $e')),
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
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('Enable Two-Factor Authentication'),
                      subtitle: const Text('Require a 2FA code for login'),
                      value: _tfaActive,
                      onChanged: (value) => setState(() {
                        _tfaActive = value;
                        if (!value) _useTfaForPasswordChange = false;
                      }),
                    ),
                    if (_tfaActive) ...[
                      const SizedBox(height: 8),
                      SwitchListTile(
                        title: const Text('Require 2FA for Password Change'),
                        subtitle: const Text('Use a verification code instead of current password'),
                        value: _useTfaForPasswordChange,
                        onChanged: (value) => setState(() => _useTfaForPasswordChange = value),
                      ),
                    ],
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _saveProfile,
                      child: const Text('Save Profile'),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'Change Password',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Form(
                      key: _passwordFormKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!_useTfaForPasswordChange || !_tfaActive)
                            TextFormField(
                              controller: _oldPasswordController,
                              decoration: InputDecoration(
                                labelText: 'Current Password',
                                border: const OutlineInputBorder(),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _isOldPasswordVisible ? Icons.visibility : Icons.visibility_off,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _isOldPasswordVisible = !_isOldPasswordVisible;
                                    });
                                  },
                                ),
                              ),
                              obscureText: !_isOldPasswordVisible,
                              validator: (value) {
                                if (!_useTfaForPasswordChange && (value?.isEmpty ?? true)) {
                                  return 'Current password is required';
                                }
                                return null;
                              },
                            ),
                          if (_useTfaForPasswordChange && _tfaActive) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _tfaCodeController,
                                    decoration: const InputDecoration(
                                      labelText: '2FA Code',
                                      border: OutlineInputBorder(),
                                    ),
                                    validator: (value) {
                                      if (_useTfaForPasswordChange && (value?.isEmpty ?? true)) {
                                        return '2FA code is required';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: _sendTfaCode,
                                  child: const Text('Send Code'),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _newPasswordController,
                            decoration: InputDecoration(
                              labelText: 'New Password',
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _isNewPasswordVisible ? Icons.visibility : Icons.visibility_off,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isNewPasswordVisible = !_isNewPasswordVisible;
                                  });
                                },
                              ),
                            ),
                            obscureText: !_isNewPasswordVisible,
                            validator: (value) {
                              if (value?.isEmpty ?? true) return 'New password is required';
                              if (value!.length < 6) return 'Password must be at least 6 characters';
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _confirmPasswordController,
                            decoration: InputDecoration(
                              labelText: 'Confirm New Password',
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _isConfirmPasswordVisible ? Icons.visibility : Icons.visibility_off,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
                                  });
                                },
                              ),
                            ),
                            obscureText: !_isConfirmPasswordVisible,
                            validator: (value) {
                              if (value?.isEmpty ?? true) return 'Please confirm new password';
                              if (value != _newPasswordController.text) return 'Passwords do not match';
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _isLoading ? null : _changePassword,
                            child: const Text('Change Password'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}