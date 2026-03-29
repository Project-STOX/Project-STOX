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

  void verifyCode() async {
    setState(() => isLoading = true);

    final enteredCode = codeController.text.trim();
    final isValid = await authController.verify2FA(widget.user.userId, enteredCode);

    setState(() => isLoading = false);

    if (isValid) {
      // Navigate to dashboard with user object
      Navigator.pushReplacementNamed(context, '/dashboard', arguments: widget.user);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Invalid 2FA code")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Two-Factor Authentication")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text("Enter the 6-digit code sent to your email"),
            TextField(
              controller: codeController,
              decoration: InputDecoration(labelText: "Authentication Code"),
              keyboardType: TextInputType.number,
            ),
            SizedBox(height: 20),
            isLoading
                ? CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: verifyCode,
                    child: Text("Verify"),
                  ),
          ],
        ),
      ),
    );
  }
}
