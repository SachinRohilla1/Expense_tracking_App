import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/auth_service.dart';
import 'package:my_first_app/device_authentication.dart';
import 'package:my_first_app/expense_transaction.dart';
import 'package:my_first_app/main.dart';
import 'package:my_first_app/transaction_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestAuthService implements AuthService {
  _TestAuthService({bool signedIn = true}) {
    if (signedIn) {
      _currentUser = const AppUser(id: 'test-user', email: 'test@example.com');
    }
  }

  final _changes = StreamController<AppUser?>.broadcast();
  AppUser? _currentUser;

  @override
  Stream<AppUser?> get authStateChanges async* {
    yield _currentUser;
    yield* _changes.stream;
  }

  @override
  Future<void> createAccount(String email, String password) async {
    _updateUser(email);
  }

  @override
  Future<void> reauthenticate(String email, String password) async {}

  @override
  Future<void> signIn(String email, String password) async {
    _updateUser(email);
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
    _changes.add(null);
  }

  void _updateUser(String email) {
    _currentUser = AppUser(id: email, email: email);
    _changes.add(_currentUser);
  }

  Future<void> dispose() => _changes.close();
}

class _MemorySecureValueStore implements SecureValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _TestDeviceAuthenticator implements DeviceAuthenticator {
  const _TestDeviceAuthenticator();

  @override
  Future<bool> authenticate() async => true;
}

Widget _authenticatedApp() {
  final authService = _TestAuthService();
  addTearDown(authService.dispose);
  return ExpenseApp(
    authService: authService,
    deviceAuthenticator: const _TestDeviceAuthenticator(),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'local accounts securely authenticate and persist their session',
    () async {
      final storage = _MemorySecureValueStore();
      final passwordHasher = Pbkdf2.hmacSha256(iterations: 1000, bits: 256);
      final authService = LocalAuthService(
        storage: storage,
        passwordHasher: passwordHasher,
      );

      await authService.createAccount('User@Example.com', 'correct-horse');
      final signedInUser = await authService.authStateChanges.first;
      expect(signedInUser?.email, 'user@example.com');
      expect(storage.values.values, isNot(contains('correct-horse')));

      await authService.signOut();
      await expectLater(
        authService.signIn('user@example.com', 'incorrect-password'),
        throwsA(
          isA<LocalAuthException>().having(
            (error) => error.message,
            'message',
            'Email or password is incorrect.',
          ),
        ),
      );
      await authService.signIn('USER@example.com', 'correct-horse');

      final restoredService = LocalAuthService(
        storage: storage,
        passwordHasher: passwordHasher,
      );
      final restoredUser = await restoredService.authStateChanges.first;
      expect(restoredUser?.id, signedInUser?.id);
      expect(restoredUser?.email, 'user@example.com');
    },
  );

  test('local accounts reject duplicate email addresses', () async {
    final authService = LocalAuthService(
      storage: _MemorySecureValueStore(),
      passwordHasher: Pbkdf2.hmacSha256(iterations: 1000, bits: 256),
    );

    await authService.createAccount('user@example.com', 'correct-horse');
    await expectLater(
      authService.createAccount('USER@example.com', 'another-password'),
      throwsA(isA<LocalAuthException>()),
    );
  });

  testWidgets('signed-out users can sign in before opening the dashboard', (
    tester,
  ) async {
    final authService = _TestAuthService(signedIn: false);
    addTearDown(authService.dispose);

    await tester.pumpWidget(
      ExpenseApp(
        authService: authService,
        deviceAuthenticator: const _TestDeviceAuthenticator(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'user@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'correct-horse',
    );
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('My Dashboard'), findsOneWidget);
    expect(find.text('Unlock Expense Tracker'), findsNothing);
  });

  testWidgets('new users can create an account from the sign-in screen', (
    tester,
  ) async {
    final authService = LocalAuthService(
      storage: _MemorySecureValueStore(),
      passwordHasher: Pbkdf2.hmacSha256(iterations: 1000, bits: 256),
    );

    await tester.pumpWidget(
      ExpenseApp(
        authService: authService,
        deviceAuthenticator: const _TestDeviceAuthenticator(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('New here? Create an account'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'new@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'correct-horse',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm password'),
      'correct-horse',
    );
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(find.text('My Dashboard'), findsOneWidget);
  });

  testWidgets('authenticated dashboard relocks after app backgrounding', (
    tester,
  ) async {
    await tester.pumpWidget(_authenticatedApp());
    await tester.pumpAndSettle();
    expect(find.text('My Dashboard'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(find.text('Unlock Expense Tracker'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('My Dashboard'), findsOneWidget);
  });

  testWidgets('date and sort filters fit on a narrow phone screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_authenticatedApp());
    await tester.pumpAndSettle();
    expect(find.text('Recent Transactions'), findsOneWidget);
    await tester.ensureVisible(find.text('Newest'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Newest'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Highest amount').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('All time'));
    await tester.tap(find.text('All time'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('This month').last);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard starts empty and saves expense transactions', (
    tester,
  ) async {
    await tester.pumpWidget(_authenticatedApp());
    await tester.pumpAndSettle();

    expect(find.text('₹ 0.00'), findsOneWidget);
    expect(find.text('No transactions yet. Tap + to add one.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Transport');
    await tester.enterText(find.byType(TextFormField).at(1), '125.50');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('₹ -125.50'), findsOneWidget);
    expect(find.text('₹ 125.50'), findsOneWidget);
    expect(find.text('Transport'), findsOneWidget);
    expect(find.text('- ₹ 125.50'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_authenticatedApp());
    await tester.pumpAndSettle();
    expect(find.text('Transport'), findsOneWidget);
    expect(find.text('₹ -125.50'), findsOneWidget);
  });

  testWidgets('adding income updates balance and reports', (tester) async {
    await tester.pumpWidget(_authenticatedApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<TransactionType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Income').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Freelance');
    await tester.enterText(find.byType(TextFormField).at(1), '2000');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('₹ 2,000'), findsOneWidget);
    expect(find.text('₹ 2,000.00'), findsOneWidget);
    expect(find.text('Freelance'), findsOneWidget);
    expect(find.text('+ ₹ 2,000'), findsOneWidget);

    await tester.tap(find.byTooltip('Reports'));
    await tester.pumpAndSettle();
    expect(find.text('Monthly report'), findsOneWidget);
    expect(find.text('Income this month'), findsOneWidget);
    expect(find.text('₹ 2,000'), findsOneWidget);
  });

  testWidgets('invalid transaction amounts are rejected', (tester) async {
    await tester.pumpWidget(_authenticatedApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Invalid');
    await tester.enterText(find.byType(TextFormField).at(1), '0');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Amount must be greater than zero'), findsOneWidget);
    expect(find.text('No transactions yet. Tap + to add one.'), findsOneWidget);
  });

  testWidgets('transactions can be edited and deleted', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_authenticatedApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Lunch');
    await tester.enterText(find.byType(TextFormField).at(1), '250');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Lunch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lunch'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Dinner');
    await tester.enterText(find.byType(TextFormField).at(1), '350');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(find.text('Dinner'), findsOneWidget);
    expect(find.text('- ₹ 350'), findsOneWidget);
    expect(find.text('Lunch'), findsNothing);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(find.text('No transactions yet. Tap + to add one.'), findsOneWidget);
  });

  testWidgets(
    'monthly and yearly budgets save and search filters transactions',
    (tester) async {
      await tester.pumpWidget(_authenticatedApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Set Monthly budget'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '1000');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('₹ 1,000 remaining'), findsOneWidget);

      await tester.ensureVisible(find.text('Set Yearly budget'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set Yearly budget'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '12000');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('₹ 12,000 remaining'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Groceries');
      await tester.enterText(find.byType(TextFormField).at(1), '250');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('₹ 250 of ₹ 1,000 used'), findsOneWidget);
      expect(find.text('₹ 250 of ₹ 12,000 used'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'Food');
      await tester.pumpAndSettle();
      expect(find.text('Groceries'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'does not exist');
      await tester.pumpAndSettle();
      expect(find.text('No transactions match these filters.'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_authenticatedApp());
      await tester.pumpAndSettle();
      expect(find.text('₹ 250 of ₹ 1,000 used'), findsOneWidget);
      expect(find.text('₹ 250 of ₹ 12,000 used'), findsOneWidget);
      expect(find.text('Groceries'), findsOneWidget);

      await tester.tap(find.byTooltip('Reports'));
      await tester.pumpAndSettle();
      expect(find.text('Budget overview'), findsOneWidget);
      expect(find.text('Total monthly budget'), findsOneWidget);
      expect(find.text('₹ 1,000'), findsWidgets);

      await tester.tap(find.text('Bars'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yearly'));
      await tester.pumpAndSettle();
      expect(find.text('Total yearly budget'), findsOneWidget);
      expect(find.text('₹ 12,000'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('recurring expense is added and is not duplicated on restart', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_authenticatedApp());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Recurring expenses'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Rent');
    await tester.enterText(find.byType(TextFormField).at(1), '900');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    expect(find.text('Rent'), findsNWidgets(2));
    expect(find.text('- ₹ 900'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_authenticatedApp());
    await tester.pumpAndSettle();

    expect(find.text('Rent'), findsNWidgets(2));
    expect(find.text('- ₹ 900'), findsOneWidget);
  });

  test('transaction storage is isolated by authenticated user', () async {
    final alice = TransactionStorage(userId: 'alice');
    final bob = TransactionStorage(userId: 'bob');

    await alice.saveMonthlyBudget(125000);

    expect(await alice.loadMonthlyBudget(), 125000);
    expect(await bob.loadMonthlyBudget(), 0);
  });

  test('existing device data is migrated to only the first account', () async {
    await TransactionStorage().saveMonthlyBudget(250000);

    final alice = TransactionStorage(userId: 'alice');
    final bob = TransactionStorage(userId: 'bob');

    expect(await alice.loadMonthlyBudget(), 250000);
    expect(await bob.loadMonthlyBudget(), 0);
  });
}
