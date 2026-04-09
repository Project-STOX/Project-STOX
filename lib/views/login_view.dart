import 'package:flutter/material.dart';
import '../controllers/auth_controller.dart';
import '../models/user.dart';
import 'two_factor_view.dart'; // import the 2FA screen

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  _LoginViewState createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  static const String _loginLogoAssetPath = 'assets/images/stox_logo.png';

  final AuthController authController = AuthController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = true;
  bool _isAutoLoggingIn = true;

  @override
  void initState() {
    super.initState();
    _checkAutoLogin();
  }

  Future<void> _checkAutoLogin() async {
    final user = await authController.tryAutoLogin();
    if (user != null && mounted) {
      Navigator.pushReplacementNamed(
        context,
        '/dashboard',
        arguments: user,
      );
    } else {
      if (mounted) {
        setState(() => _isAutoLoggingIn = false);
      }
    }
  }

  void login() async {
    try {
      final loginResponse = await authController.signIn(
        emailController.text.trim(),
        passwordController.text,
        rememberMe: _rememberMe,
      );

      if (!mounted) return;

      final accessToken = loginResponse['access_token']?.toString();
      final refreshToken = loginResponse['refresh_token']?.toString();
      if (accessToken != null && accessToken.isNotEmpty && refreshToken != null && refreshToken.isNotEmpty) {
        final userPayload = loginResponse['user'] as Map<String, dynamic>?;
        if (userPayload == null) {
          throw Exception('Login response missing user payload');
        }
        Navigator.pushReplacementNamed(
          context,
          '/dashboard',
          arguments: UserModel.fromJson(userPayload),
        );
        return;
      }

      final loginChallenge = loginResponse['login_challenge']?.toString();
      if (loginChallenge == null || loginChallenge.isEmpty) {
        throw Exception('Invalid login response');
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TwoFactorView(
            loginChallenge: loginChallenge,
            email: emailController.text.trim(),
            rememberMe: _rememberMe,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Login error: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isAutoLoggingIn) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

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
                    errorBuilder: (_, _, _) => const Column(
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
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Checkbox(
                    value: _rememberMe,
                    onChanged: (val) => setState(() => _rememberMe = val ?? false),
                  ),
                  const Text("Remember Me"),
                ],
              ),
              const SizedBox(height: 20),
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
