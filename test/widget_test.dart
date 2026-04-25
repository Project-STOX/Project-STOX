import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:project_stox/controllers/auth_controller.dart';
import 'package:project_stox/models/user.dart';
import 'package:project_stox/views/login_view.dart';
import 'package:project_stox/views/two_factor_view.dart';

class FakeAuthController extends AuthController {
  FakeAuthController({
    this.autoLoginUser,
    this.loginResponse,
    this.verifyUser,
    this.signInError,
    this.verifyError,
    this.generate2faError,
  });

  final UserModel? autoLoginUser;
  final Map<String, dynamic>? loginResponse;
  final UserModel? verifyUser;
  final Object? signInError;
  final Object? verifyError;
  final Object? generate2faError;

  String? lastEmail;
  String? lastPassword;
  bool? lastRememberMe;
  String? lastLoginChallenge;
  String? lastVerifyCode;
  String? lastGeneratedEmail;

  @override
  Future<UserModel?> tryAutoLogin() async => autoLoginUser;

  @override
  Future<Map<String, dynamic>> signIn(String email, String password, {bool rememberMe = true}) async {
    lastEmail = email;
    lastPassword = password;
    lastRememberMe = rememberMe;
    if (signInError != null) {
      throw signInError!;
    }
    return loginResponse ??
        {
          'access_token': 'access-token',
          'refresh_token': 'refresh-token',
          'user': {
            'id': 1,
            'email': email,
            'full_name': 'Test User',
            'role': 'Admin',
            'role_id': 1,
            'is_active': true,
            'tfa_active': false,
            'totp_enabled': false,
          },
        };
  }

  @override
  Future<UserModel> verify2FA(String loginChallenge, String code, {bool rememberMe = true}) async {
    lastLoginChallenge = loginChallenge;
    lastVerifyCode = code;
    lastRememberMe = rememberMe;
    if (verifyError != null) {
      throw verifyError!;
    }
    return verifyUser ??
        UserModel(
          id: 2,
          fullName: 'Two Factor User',
          email: 'twofactor@stox.local',
          role: 'Admin',
          roleIdValue: 1,
          isActive: true,
          tfaActiveValue: false,
          totpEnabledValue: false,
        );
  }

  @override
  Future<void> generate2FAByEmail(String email) async {
    lastGeneratedEmail = email;
    if (generate2faError != null) {
      throw generate2faError!;
    }
  }
}

UserModel _testUser({int id = 1}) {
  return UserModel(
    id: id,
    fullName: 'Test User',
    email: 'test@stox.local',
    role: 'Admin',
    roleIdValue: 1,
    isActive: true,
    tfaActiveValue: false,
    totpEnabledValue: false,
  );
}

Widget _wrapApp(Widget child) {
  return MaterialApp(
    routes: {
      '/dashboard': (_) => const Scaffold(body: Text('DASHBOARD')),
    },
    home: child,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Login view shows form after auto-login fails', (tester) async {
    final fakeController = FakeAuthController(autoLoginUser: null);

    await tester.pumpWidget(
      _wrapApp(LoginView(authController: fakeController)),
    );
    await tester.pumpAndSettle();

    expect(find.text('STOX - Login'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
  });

  testWidgets('Login view navigates to dashboard on successful login', (tester) async {
    final fakeController = FakeAuthController(autoLoginUser: null);

    await tester.pumpWidget(
      _wrapApp(LoginView(authController: fakeController)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Email'), 'admin@stox.local');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'Secret123!');
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    expect(fakeController.lastEmail, 'admin@stox.local');
    expect(fakeController.lastPassword, 'Secret123!');
    expect(find.text('DASHBOARD'), findsOneWidget);
  });

  testWidgets('Login view opens two-factor screen when challenge is returned', (tester) async {
    final fakeController = FakeAuthController(
      autoLoginUser: null,
      loginResponse: {
        'login_challenge': 'challenge-123',
        'is_totp': false,
      },
    );

    await tester.pumpWidget(
      _wrapApp(LoginView(authController: fakeController)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Email'), 'user@stox.local');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'Password1');
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    expect(find.text('Two-Factor Authentication'), findsOneWidget);
    expect(find.text('Authentication Code'), findsOneWidget);
    expect(fakeController.lastEmail, 'user@stox.local');
  });

  testWidgets('Two-factor view verifies code and navigates to dashboard', (tester) async {
    final fakeController = FakeAuthController();

    await tester.pumpWidget(
      _wrapApp(
        TwoFactorView(
          loginChallenge: 'challenge-123',
          email: 'user@stox.local',
          authController: fakeController,
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.widgetWithText(TextField, 'Authentication Code'), '123456');
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();

    expect(fakeController.lastLoginChallenge, 'challenge-123');
    expect(fakeController.lastVerifyCode, '123456');
    expect(find.text('DASHBOARD'), findsOneWidget);
  });

  testWidgets('Two-factor view shows snackbar on invalid code', (tester) async {
    final fakeController = FakeAuthController(verifyError: Exception('Invalid code'));

    await tester.pumpWidget(
      _wrapApp(
        TwoFactorView(
          loginChallenge: 'challenge-123',
          email: 'user@stox.local',
          authController: fakeController,
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.widgetWithText(TextField, 'Authentication Code'), '999999');
    await tester.tap(find.text('Verify'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Invalid code'), findsOneWidget);
  });

  testWidgets('Two-factor resend code calls generate2FAByEmail', (tester) async {
    final fakeController = FakeAuthController();

    await tester.pumpWidget(
      _wrapApp(
        TwoFactorView(
          loginChallenge: 'challenge-123',
          email: 'user@stox.local',
          authController: fakeController,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Resend Code'));
    await tester.pumpAndSettle();

    expect(fakeController.lastGeneratedEmail, 'user@stox.local');
    expect(find.text('A new code has been sent.'), findsOneWidget);
  });

  testWidgets('Login view keeps remember me selected by default', (tester) async {
    final fakeController = FakeAuthController(autoLoginUser: null);

    await tester.pumpWidget(
      _wrapApp(LoginView(authController: fakeController)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Checkbox), findsOneWidget);
    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.value, isTrue);
  });
}

