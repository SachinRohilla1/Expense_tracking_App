import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'expense_transaction.dart';
import 'recurring_expense.dart';

class TransactionStorage {
  TransactionStorage({this.userId});

  static const _legacyTransactionsKey = 'expense_tracker_transactions_v1';
  static const _legacyMonthlyBudgetKey = 'expense_tracker_monthly_budget_v1';
  static const _legacyYearlyBudgetKey = 'expense_tracker_yearly_budget_v1';
  static const _legacyRecurringExpensesKey =
      'expense_tracker_recurring_expenses_v1';
  static const _dataOwnerKey = 'expense_tracker_data_migration_owner_v1';

  final String? userId;

  String get _userPrefix =>
      'expense_tracker_user_${base64Url.encode(utf8.encode(userId!))}';
  String get _transactionsKey => userId == null
      ? _legacyTransactionsKey
      : '${_userPrefix}_transactions_v1';
  String get _monthlyBudgetKey => userId == null
      ? _legacyMonthlyBudgetKey
      : '${_userPrefix}_monthly_budget_v1';
  String get _yearlyBudgetKey => userId == null
      ? _legacyYearlyBudgetKey
      : '${_userPrefix}_yearly_budget_v1';
  String get _recurringExpensesKey => userId == null
      ? _legacyRecurringExpensesKey
      : '${_userPrefix}_recurring_expenses_v1';
  Future<void>? _migration;

  Future<SharedPreferences> _getPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    if (userId == null) return preferences;

    final owner = preferences.getString(_dataOwnerKey);
    if (owner == null) {
      final migration = _migration ??= _migrateLegacyData(preferences);
      try {
        await migration;
      } catch (_) {
        _migration = null;
        rethrow;
      }
    }
    return preferences;
  }

  Future<void> _migrateLegacyData(SharedPreferences preferences) async {
    await _copyPreference(
      preferences,
      _legacyTransactionsKey,
      _transactionsKey,
    );
    await _copyPreference(
      preferences,
      _legacyMonthlyBudgetKey,
      _monthlyBudgetKey,
    );
    await _copyPreference(
      preferences,
      _legacyYearlyBudgetKey,
      _yearlyBudgetKey,
    );
    await _copyPreference(
      preferences,
      _legacyRecurringExpensesKey,
      _recurringExpensesKey,
    );

    final saved = await preferences.setString(_dataOwnerKey, userId!);
    if (!saved) {
      throw StateError('Could not assign existing data to this account.');
    }
  }

  Future<void> _copyPreference(
    SharedPreferences preferences,
    String oldKey,
    String newKey,
  ) async {
    if (!preferences.containsKey(oldKey) || preferences.containsKey(newKey)) {
      return;
    }

    final value = preferences.get(oldKey);
    final bool saved;
    if (value is String) {
      saved = await preferences.setString(newKey, value);
    } else if (value is int) {
      saved = await preferences.setInt(newKey, value);
    } else {
      throw StateError('Saved data for "$oldKey" has an unsupported format.');
    }
    if (!saved) {
      throw StateError('Could not move existing data for "$oldKey".');
    }
  }

  Future<List<ExpenseTransaction>> loadTransactions() async {
    final preferences = await _getPreferences();
    final encoded = preferences.getString(_transactionsKey);
    if (encoded == null) {
      return [];
    }

    final decoded = jsonDecode(encoded) as List<dynamic>;
    List<ExpenseTransaction> transactions = [];
    for (final item in decoded) {
      transactions.add(
        ExpenseTransaction.fromJson(item as Map<String, dynamic>),
      );
    }
    return transactions;
  }

  Future<void> saveTransactions(List<ExpenseTransaction> transactions) async {
    final preferences = await _getPreferences();
    List<Map<String, Object>> savedTransactions = [];
    for (final transaction in transactions) {
      savedTransactions.add(transaction.toJson());
    }

    final saved = await preferences.setString(
      _transactionsKey,
      jsonEncode(savedTransactions),
    );
    if (!saved) throw StateError('Could not save transactions on this device.');
  }

  Future<int> loadMonthlyBudget() async {
    final preferences = await _getPreferences();
    return preferences.getInt(_monthlyBudgetKey) ?? 0;
  }

  Future<void> saveMonthlyBudget(int amountInPaise) async {
    final preferences = await _getPreferences();
    final saved = await preferences.setInt(_monthlyBudgetKey, amountInPaise);
    if (!saved) throw StateError('Could not save the monthly budget.');
  }

  Future<int> loadYearlyBudget() async {
    final preferences = await _getPreferences();
    return preferences.getInt(_yearlyBudgetKey) ?? 0;
  }

  Future<void> saveYearlyBudget(int amountInPaise) async {
    final preferences = await _getPreferences();
    final saved = await preferences.setInt(_yearlyBudgetKey, amountInPaise);
    if (!saved) throw StateError('Could not save the yearly budget.');
  }

  Future<List<RecurringExpense>> loadRecurringExpenses() async {
    final preferences = await _getPreferences();
    final encoded = preferences.getString(_recurringExpensesKey);
    if (encoded == null) {
      return [];
    }

    final decoded = jsonDecode(encoded) as List<dynamic>;
    List<RecurringExpense> expenses = [];
    for (final item in decoded) {
      expenses.add(RecurringExpense.fromJson(item as Map<String, dynamic>));
    }
    return expenses;
  }

  Future<void> saveRecurringExpenses(List<RecurringExpense> expenses) async {
    final preferences = await _getPreferences();
    List<Map<String, Object>> savedExpenses = [];
    for (final expense in expenses) {
      savedExpenses.add(expense.toJson());
    }

    final saved = await preferences.setString(
      _recurringExpensesKey,
      jsonEncode(savedExpenses),
    );
    if (!saved) {
      throw StateError('Could not save recurring expenses on this device.');
    }
  }
}
