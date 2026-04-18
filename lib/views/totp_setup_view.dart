import 'package:flutter/material.dart';
import 'dart:convert';
import '../controllers/auth_controller.dart';
import '../services/api/auth_api_service.dart';

class TOTPSetupView extends StatefulWidget {
  const TOTPSetupView({super.key});

  @override
  State<TOTPSetupView> createState() => _TOTPSetupViewState();
}

class _TOTPSetupViewState extends State<TOTPSetupView> {
  final AuthController authController = AuthController();
  final TextEditingController codeController = TextEditingController();

  bool isLoading = false;
  bool setupInitiated = false;
  String? qrCodeBase64;
  List<String> backupCodes = [];
  String? secret;

  @override
  void initState() {
    super.initState();
    _initiateSetup();
  }

  void _initiateSetup() async {
    setState(() => isLoading = true);
    try {
      final response = await authController.setupTOTP();

      setState(() {
        secret = response['secret'] as String?;
        qrCodeBase64 = response['qr_code'] as String?;
        backupCodes = List<String>.from(response['backup_codes'] as List? ?? []);
        setupInitiated = true;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error initiating TOTP setup: $e")),
      );
    }
  }

  void _verifyAndEnable() async {
    final code = codeController.text.trim();
    if (code.isEmpty || code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a 6-digit code")),
      );
      return;
    }

    setState(() => isLoading = true);
    try {
      final updatedBackupCodes = await authController.verifyTOTPSetup(code);

      if (!mounted) return;
      setState(() {
        backupCodes = updatedBackupCodes;
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("TOTP enabled successfully!")),
      );
      Navigator.of(context).pop(true); // Return true to indicate success
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Verification failed: $e")),
      );
    }
  }

  @override
  void dispose() {
    codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Set Up TOTP Authentication")),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : setupInitiated
              ? _buildSetupContent()
              : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildSetupContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // QR Code Section
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const Text(
                    "Scan this QR code with your authenticator app",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 16),
                  if (qrCodeBase64 != null)
                    Image.memory(
                      base64Decode(qrCodeBase64!.split(',').last),
                      width: 250,
                      height: 250,
                    )
                  else
                    const Text("Failed to generate QR code"),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Manual entry section
          if (secret != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Or enter manually:",
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        secret!,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),

          // Backup codes section
          if (backupCodes.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Save these backup codes in a safe place",
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        border: Border.all(color: Colors.orange[200]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          for (int i = 0; i < backupCodes.length; i++)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: SelectableText(
                                "${i + 1}. ${backupCodes[i]}",
                                style: const TextStyle(fontFamily: 'monospace'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),

          // Verification section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Verify setup",
                    style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Enter the 6-digit code from your authenticator app to complete setup:",
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: codeController,
                    decoration: const InputDecoration(
                      labelText: "6-digit code",
                      border: OutlineInputBorder(),
                      hintText: "000000",
                    ),
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : _verifyAndEnable,
                      child: isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text("Enable TOTP"),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
