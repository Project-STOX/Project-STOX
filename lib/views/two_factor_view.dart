import 'dart:async';
import 'package:flutter/material.dart';
import '../controllers/auth_controller.dart';

class TwoFactorView extends StatefulWidget {
  final String loginChallenge;
  final String email;
  final bool rememberMe;
  final bool isTotp;
  final AuthController? authController;

  const TwoFactorView({
    super.key,
    required this.loginChallenge,
    required this.email,
    this.rememberMe = true,
    this.isTotp = false,
    this.authController,
  });

  @override
// Handles createState.
  _TwoFactorViewState createState() => _TwoFactorViewState();
}

class _TwoFactorViewState extends State<TwoFactorView> {
  late final AuthController authController;
  final TextEditingController codeController = TextEditingController();
  bool isLoading = false;

  late Timer _timer;
  int _remainingSeconds = 300; // 5 minutes = 300 seconds

  @override
// Handles initState.
  void initState() {
    super.initState();
    authController = widget.authController ?? AuthController();
    _startCountdown();
  }

// Handles _startCountdown.
  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        _timer.cancel();
      }
    });
  }

  @override
// Handles dispose.
  void dispose() {
    _timer.cancel();
    codeController.dispose();
    super.dispose();
  }

// Handles verifyCode.
  void verifyCode() async {
    setState(() => isLoading = true);

    final enteredCode = codeController.text.trim();
    try {
      final user = await authController.verify2FA(
        widget.loginChallenge,
        enteredCode,
        rememberMe: widget.rememberMe,
      );
      if (!mounted) return;
      setState(() => isLoading = false);
      Navigator.pushReplacementNamed(context, '/dashboard', arguments: user);
    } catch (_) {
      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Invalid code")),
      );
    }
  }

// Handles resendCode.
  void resendCode() async {
    setState(() => isLoading = true);
    try {
      await authController.generate2FAByEmail(widget.email);
      if (!mounted) return;
      setState(() {
        isLoading = false;
        _remainingSeconds = 300;
      });
      _timer.cancel();
      _startCountdown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("A new code has been sent.")),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);

      String displayMessage = "Error resending code: $e";
      if (e.toString().contains("429") || e.toString().contains("limit exceeded")) {
        displayMessage = "Supabase free limit exceeded. Please wait an hour or contact support.";
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(displayMessage),
          backgroundColor: e.toString().contains("429") ? Colors.orange : null,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

// Handles _formatTime.
  String _formatTime(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return "$minutes:$secs";
  }

  @override
// Handles build.
  Widget build(BuildContext context) {
    final isTotpMode = widget.isTotp;

    return Scaffold(
      appBar: AppBar(
        title: Text(isTotpMode ? "Enter Authentication Code" : "Two-Factor Authentication"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              isTotpMode
                  ? "Enter the code from your authenticator app or a backup code"
                  : "Enter the code sent to ${widget.email}",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: codeController,
              decoration: InputDecoration(
                labelText: isTotpMode ? "Code / Backup Code" : "Authentication Code",
                border: const OutlineInputBorder(),
                hintText: isTotpMode ? "Enter code" : "000000",
              ),
              keyboardType: TextInputType.text,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              _remainingSeconds > 0
                  ? (isTotpMode
                      ? "Code refreshes every 30 seconds"
                      : "Code expires in ${_formatTime(_remainingSeconds)}")
                  : "Code has expired. Please try again.",
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 20),
            isLoading
// Handles CircularProgressIndicator.
                ? const CircularProgressIndicator()
                : Column(
                    children: [
                      ElevatedButton(
                        onPressed: _remainingSeconds > 0 ? verifyCode : null,
                        child: const Text("Verify"),
                      ),
                      const SizedBox(height: 10),
                      if (!isTotpMode)
                        OutlinedButton(
                          onPressed: resendCode,
                          child: const Text("Resend Code"),
                        ),
                      if (isTotpMode)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            "Don't have your phone? Use a backup code instead",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}
