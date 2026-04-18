import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import '../controllers/auth_controller.dart';

class TOTPSetupDialog extends StatefulWidget {
  final dynamic user; // Using dynamic to avoid hard dependency in this snippet
  const TOTPSetupDialog({super.key, required this.user});

  @override
  State<TOTPSetupDialog> createState() => _TOTPSetupDialogState();
}

class _TOTPSetupDialogState extends State<TOTPSetupDialog> {
  final AuthController _authController = AuthController();
  final TextEditingController _codeController = TextEditingController();
  
  bool _isLoading = true;
  bool _isVerifying = false;
  String? _secret;
  String? _qrData;
  List<String>? _backupCodes;
  String? _errorMessage;
  int _step = 1; // 1: QR Scan, 2: Backup Codes

  @override
  void initState() {
    super.initState();
    _loadSetupData();
  }

  Future<void> _loadSetupData() async {
    try {
      final data = await _authController.setupTOTP();
      if (mounted) {
        setState(() {
          _secret = data['secret'];
          _qrData = data['qr_code']; // This is now a Base64 string from backend
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _verifySetup() async {
    if (_codeController.text.length != 6) return;

    setState(() => _isVerifying = true);
    try {
      final codes = await _authController.verifyTOTPSetup(_codeController.text);
      
      if (mounted) {
        setState(() {
          _backupCodes = codes;
          _step = 2;
          _isVerifying = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVerifying = false;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Verification failed: $e')),
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return AlertDialog(
      title: Text(_step == 1 ? 'Setup Authenticator App' : 'Save Backup Codes'),
      content: SizedBox(
        width: 400,
        child: _isLoading 
          ? const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))
          : _errorMessage != null
            ? Text('Error: $_errorMessage')
            : _step == 1 
              ? _buildSetupStep(theme)
              : _buildBackupStep(theme),
      ),
      actions: _step == 1 
        ? [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: _isVerifying ? null : _verifySetup,
              child: _isVerifying 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Verify & Enable'),
            ),
          ]
        : [
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('I have saved my codes'),
            ),
          ],
    );
  }

  Widget _buildSetupStep(ThemeData theme) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '1. Scan this QR code with your authenticator app (e.g., Google Authenticator, Authy, or Microsoft Authenticator).',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 20),
          if (_qrData != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Image.memory(
                base64Decode(_qrData!.split(',').last),
                width: 200,
                height: 200,
              ),
            ),
          const SizedBox(height: 20),
          const Text(
            'Or enter this secret key manually:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () {
              if (_secret != null) {
                Clipboard.setData(ClipboardData(text: _secret!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Secret copied to clipboard')),
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_secret ?? '', style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                  const SizedBox(width: 8),
                  const Icon(Icons.copy, size: 14),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          const Text(
            '2. Enter the 6-digit code from the app to confirm setup:',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeController,
            decoration: const InputDecoration(
              hintText: '000 000',
              border: OutlineInputBorder(),
              counterText: '',
            ),
            maxLength: 6,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, letterSpacing: 8),
            onSubmitted: (_) => _verifySetup(),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupStep(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Two-factor authentication is now enabled! If you lose your phone, you can use these backup codes to log in.',
          style: TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.amber.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber),
          ),
          child: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.amber),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Store these codes in a safe place. Each code can only be used once.',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text('Your official backup codes:'),
        const SizedBox(height: 8),
        if (_backupCodes != null && _backupCodes!.isNotEmpty)
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _backupCodes!.map((code) => 
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(code, style: const TextStyle(fontFamily: 'monospace')),
              ),
            ).toList(),
          )
        else
          const Text('Error: No backup codes returned. Please contact support.', style: TextStyle(color: Colors.red)),
      ],
    );
  }
}
