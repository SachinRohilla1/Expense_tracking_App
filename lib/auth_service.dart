import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppUser {
  const AppUser({required this.id, required this.email});

  final String id;
  final String email;
}

class LocalAuthException implements Exception {
  const LocalAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class AuthService {
  Stream<AppUser?> get authStateChanges;
  Future<void> createAccount(String email, String password);
  Future<void> reauthenticate(String email, String password);
  Future<void> signIn(String email, String password);
  Future<void> signOut();
}

abstract interface class SecureValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureValueStore implements SecureValueStore {
  FlutterSecureValueStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class LocalAuthService implements AuthService {
  LocalAuthService({
    SecureValueStore? storage,
    Pbkdf2? passwordHasher,
  }) : _storage = storage ?? FlutterSecureValueStore(),
       _passwordHasher =
           passwordHasher ??
           Pbkdf2.hmacSha256(iterations: _passwordIterations, bits: 256);

  static const _usersKey = 'expense_tracker_local_users_v1';
  static const _sessionKey = 'expense_tracker_local_session_v1';
  static const _passwordIterations = 120000;

  final SecureValueStore _storage;
  final Pbkdf2 _passwordHasher;
  final _authChanges = StreamController<AppUser?>.broadcast();
  Future<AppUser?>? _sessionFuture;

  @override
  Stream<AppUser?> get authStateChanges async* {
    yield await _loadSession();
    yield* _authChanges.stream;
  }

  Future<AppUser?> _loadSession() {
    return _sessionFuture ??= _readSession();
  }

  Future<AppUser?> _readSession() async {
    final email = await _storage.read(_sessionKey);
    if (email == null) return null;

    final accounts = await _readAccounts();
    final account = accounts[email];
    if (account == null) {
      await _storage.delete(_sessionKey);
      return null;
    }

    return AppUser(id: account['id']! as String, email: email);
  }

  @override
  Future<void> createAccount(String email, String password) async {
    final normalizedEmail = _normalizeEmail(email);
    if (password.length < 8) {
      throw const LocalAuthException(
        'Password must be at least 8 characters.',
      );
    }

    final accounts = await _readAccounts();
    if (accounts.containsKey(normalizedEmail)) {
      throw const LocalAuthException(
        'An account already exists for that email.',
      );
    }

    final salt = _randomBytes(16);
    final passwordHash = await _hashPassword(password, salt);
    final accountId = base64Url
        .encode(_randomBytes(16))
        .replaceAll('=', '');
    accounts[normalizedEmail] = {
      'id': accountId,
      'salt': base64.encode(salt),
      'passwordHash': base64.encode(passwordHash),
    };

    await _writeAccounts(accounts);
    await _setSession(AppUser(id: accountId, email: normalizedEmail));
  }

  @override
  Future<void> signIn(String email, String password) async {
    final normalizedEmail = _normalizeEmail(email);
    final account = (await _readAccounts())[normalizedEmail];
    if (account == null) {
      throw const LocalAuthException('Email or password is incorrect.');
    }

    final salt = base64.decode(account['salt']! as String);
    final expectedHash = base64.decode(account['passwordHash']! as String);
    final actualHash = await _hashPassword(password, salt);
    if (!_constantTimeEquals(actualHash, expectedHash)) {
      throw const LocalAuthException('Email or password is incorrect.');
    }

    await _setSession(
      AppUser(id: account['id']! as String, email: normalizedEmail),
    );
  }

  @override
  Future<void> reauthenticate(String email, String password) async {
    final user = await _loadSession();
    if (user == null || user.email != _normalizeEmail(email)) {
      throw const LocalAuthException('Sign in again to unlock this account.');
    }
    await signIn(email, password);
  }

  @override
  Future<void> signOut() async {
    await _storage.delete(_sessionKey);
    _sessionFuture = Future<AppUser?>.value(null);
    _authChanges.add(null);
  }

  Future<Map<String, Map<String, Object>>> _readAccounts() async {
    final encoded = await _storage.read(_usersKey);
    if (encoded == null) return {};

    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Saved local accounts are invalid.');
    }
    return decoded.map((email, value) {
      if (value is! Map<String, dynamic> ||
          value['id'] is! String ||
          value['salt'] is! String ||
          value['passwordHash'] is! String) {
        throw const FormatException('A saved local account is invalid.');
      }
      return MapEntry(email, Map<String, Object>.from(value));
    });
  }

  Future<void> _writeAccounts(Map<String, Map<String, Object>> accounts) {
    return _storage.write(_usersKey, jsonEncode(accounts));
  }

  Future<List<int>> _hashPassword(String password, List<int> salt) async {
    final key = await _passwordHasher.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    return key.extractBytes();
  }

  Future<void> _setSession(AppUser user) async {
    await _storage.write(_sessionKey, user.email);
    _sessionFuture = Future<AppUser?>.value(user);
    _authChanges.add(user);
  }

  List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  String _normalizeEmail(String email) {
    final normalizedEmail = email.trim().toLowerCase();
    if (!normalizedEmail.contains('@') ||
        normalizedEmail.startsWith('@') ||
        normalizedEmail.endsWith('@')) {
      throw const LocalAuthException('Enter a valid email address.');
    }
    return normalizedEmail;
  }

  bool _constantTimeEquals(List<int> first, List<int> second) {
    var difference = first.length ^ second.length;
    final maxLength = max(first.length, second.length);
    for (var index = 0; index < maxLength; index++) {
      final firstByte = index < first.length ? first[index] : 0;
      final secondByte = index < second.length ? second[index] : 0;
      difference |= firstByte ^ secondByte;
    }
    return difference == 0;
  }
}
