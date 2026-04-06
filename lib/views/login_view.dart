import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../controllers/auth_controller.dart';
import 'two_factor_view.dart'; // import the 2FA screen

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  _LoginViewState createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  static const String _loginLogoAssetPath = 'assets/images/stox_logo.png';

  final AuthController authController = AuthController();
  final TextEditingController identifierController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool _obscurePassword = true;

  bool get _isMobilePlatform {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  void initState() {
    super.initState();
    _attemptAutoLoginForMobile();
  }

  Future<void> _attemptAutoLoginForMobile() async {
    if (!_isMobilePlatform) {
      return;
    }

    try {
      final user = await authController.tryAutoLoginWithRememberedSession();
      if (!mounted || user == null) {
        return;
      }

      final hasMFA = await authController.hasMFAEnabled(user.userId);
      if (!mounted) {
        return;
      }

      if (hasMFA) {
        await authController.generate2FA(user.userId);
        if (!mounted) {
          return;
        }

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => TwoFactorView(user: user)),
        );
        return;
      }

      Navigator.pushReplacementNamed(
        context,
        '/dashboard',
        arguments: user,
      );
    } catch (_) {
      // Keep user on login screen if auto-login check fails.
    }
  }

  void login() async {
    try {
      final user = await authController.signIn(
        identifierController.text.trim(),
        passwordController.text,
      );

      if (!mounted) return;

      if (user != null) {
        if (_isMobilePlatform) {
          final sessionUuid = authController.latestSessionUuid;
          if (sessionUuid != null && sessionUuid.isNotEmpty) {
            await authController.persistSessionUuidLocally(sessionUuid);
          }
        }

        // Check if 2FA is enabled for this user
        final hasMFA = await authController.hasMFAEnabled(user.userId);
        
        if (!mounted) return;

        if (hasMFA) {
          // Send 2FA code via email
          try {
            await authController.generate2FA(user.userId);
            
            if (!mounted) return;

            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => TwoFactorView(user: user)),
            );
          } catch (e) {
            if (!mounted) return;

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Failed to send 2FA code: $e")),
            );
          }
        } else {
          // No 2FA, go straight to dashboard
          await authController.logSuccessfulSystemEntry(user, viaMfa: false);
          Navigator.pushReplacementNamed(
            context,
            '/dashboard',
            arguments: user,
          );
        }
      } else {
        // Check if account is deactivated
        final isDeactivated = await authController.isAccountDeactivated(
          identifierController.text.trim(),
          passwordController.text,
        );

        if (!mounted) return;

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
      if (!mounted) return;

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
              Container(
                constraints: const BoxConstraints(maxWidth: 420),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.asset(
                    _loginLogoAssetPath,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.image_not_supported_outlined,
                          size: 46,
                          color: Colors.blueGrey,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Place logo at assets/images/stox_logo.png',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: identifierController,
                decoration: const InputDecoration(
                  labelText: "Email or Username",
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
