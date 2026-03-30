import 'package:flutter/material.dart';
import '../controllers/auth_controller.dart';
import 'two_factor_view.dart'; // import the 2FA screen

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  _LoginViewState createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final AuthController authController = AuthController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool _obscurePassword = true;

  void login() async {
    try {
      final user = await authController.signIn(
        emailController.text.trim(),
        passwordController.text.trim(),
      );

      if (user != null) {
        // Check if 2FA is enabled for this user
        final hasMFA = await authController.hasMFAEnabled(user.userId);
        if (hasMFA) {
          // Send 2FA code via email
          try {
            await authController.generate2FA(user.userId);
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => TwoFactorView(user: user)),
            );
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Failed to send 2FA code: $e")),
            );
          }
        } else {
          // No 2FA, go straight to dashboard
          Navigator.pushReplacementNamed(
            context,
            '/dashboard',
            arguments: user,
          );
        }
      } else {
        // Check if account is deactivated
        final isDeactivated = await authController.isAccountDeactivated(
          emailController.text.trim(),
          passwordController.text.trim(),
        );

        if (isDeactivated) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Account is deactivated. Please contact your administrator."),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Invalid credentials")),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Login error: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("STOX - Login"),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              TextField(
                controller: emailController,
                decoration: const InputDecoration(
                  labelText: "Email",
                  border: OutlineInputBorder(),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              TextField(
                controller: passwordController,
                decoration: InputDecoration(
                  labelText: "Password",
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
                obscureText: _obscurePassword,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: login,
                child: const Text("Login"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
