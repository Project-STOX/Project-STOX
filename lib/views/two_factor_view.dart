import 'dart:async';
import 'package:flutter/material.dart';
import '../controllers/auth_controller.dart';
import '../models/user.dart';

class TwoFactorView extends StatefulWidget {
  final UserModel user;

  const TwoFactorView({super.key, required this.user});

  @override
  _TwoFactorViewState createState() => _TwoFactorViewState();
}

class _TwoFactorViewState extends State<TwoFactorView> {
  final AuthController authController = AuthController();
  final TextEditingController codeController = TextEditingController();
  bool isLoading = false;

  late Timer _timer;
  int _remainingSeconds = 300; // 5 minutes = 300 seconds

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

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
  void dispose() {
    _timer.cancel();
    codeController.dispose();
    super.dispose();
  }

  void verifyCode() async {
    setState(() => isLoading = true);

    final enteredCode = codeController.text.trim();
    final isValid = await authController.verify2FA(widget.user.userId, enteredCode);

    if (!mounted) return;

    setState(() => isLoading = false);

    if (isValid) {
      await authController.logSuccessfulSystemEntry(widget.user, viaMfa: true);
      Navigator.pushReplacementNamed(context, '/dashboard', arguments: widget.user);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Invalid 2FA code")),
      );
    }
  }

  void resendCode() async {
    setState(() => isLoading = true);

    // Call your controller to resend the code
    await authController.generate2FA(widget.user.userId);

    _timer.cancel();
    setState(() {
      isLoading = false;
      _remainingSeconds = 300; // reset countdown
    });
    _startCountdown();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("A new code has been sent to your email.")),
    );
  }

  String _formatTime(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return "$minutes:$secs";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Two-Factor Authentication")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              "Enter the 6-digit code sent to ${widget.user.email}",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: codeController,
              decoration: const InputDecoration(
                labelText: "Authentication Code",
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              _remainingSeconds > 0
                  ? "Code expires in ${_formatTime(_remainingSeconds)}"
                  : "Code has expired. Please request a new one.",
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 20),
            isLoading
                ? const CircularProgressIndicator()
                : Column(
                    children: [
                      ElevatedButton(
                        onPressed: _remainingSeconds > 0 ? verifyCode : null,
                        child: const Text("Verify"),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: resendCode,
                        child: const Text("Resend Code"),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}
