import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';

class PasswordHasher {
  static const String _algorithmName = 'pbkdf2_sha256';
  static const int _iterations = 100000;
  static const int _saltLength = 16;
  static const int _keyLengthBytes = 32;

  static final Pbkdf2 _pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _iterations,
    bits: _keyLengthBytes * 8,
  );

  static Future<String> hashPassword(String password) async {
    final salt = _generateSalt(_saltLength);
    final secretKey = await _pbkdf2.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final hash = await secretKey.extractBytes();

    return '$_algorithmName:$_iterations:${base64Encode(salt)}:${base64Encode(hash)}';
  }

  static Future<bool> verifyPassword(String password, String storedValue) async {
    final parts = storedValue.split(':');
    if (parts.length != 4 || parts[0] != _algorithmName) {
      // Legacy fallback for older raw-password rows.
      return storedValue == password;
    }

    final iterationValue = int.tryParse(parts[1]);
    if (iterationValue == null || iterationValue <= 0) {
      return false;
    }

    final salt = base64Decode(parts[2]);
    final expectedHash = base64Decode(parts[3]);

    final algorithm = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterationValue,
      bits: expectedHash.length * 8,
    );

    final derivedKey = await algorithm.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final actualHash = await derivedKey.extractBytes();

    return _constantTimeEquals(actualHash, expectedHash);
  }

  static List<int> _generateSalt(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;

    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
