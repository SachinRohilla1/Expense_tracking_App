import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:share_plus/share_plus.dart';

import 'app_formatters.dart' as app_formatters;
import 'auth_service.dart';
import 'authentication_ui.dart';
import 'budget_overview_card.dart';
import 'device_authentication.dart';
import 'expense_transaction.dart';
import 'recurring_expense.dart';
import 'transaction_storage.dart';
import 'transaction_dialogs.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ExpenseApp(authService: LocalAuthService()));
}

class ExpenseApp extends StatelessWidget {
  const ExpenseApp({
    required this.authService,
    this.deviceAuthenticator = const LocalDeviceAuthenticator(),
    super.key,
  });

  final AuthService authService;
  final DeviceAuthenticator deviceAuthenticator;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Expense Tracker',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF4F7F5),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF147D64),
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF4F7F5),
          foregroundColor: Color(0xFF18312C),
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Color(0xFF18312C),
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFE5ECE8)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFDCE6E1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFDCE6E1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF147D64), width: 1.5),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFF147D64),
          foregroundColor: Colors.white,
          elevation: 3,
        ),
      ),
      home: AuthGate(
        authService: authService,
        deviceAuthenticator: deviceAuthenticator,
        dashboardBuilder: (user, service) =>
            DashboardScreen(user: user, authService: service),
      ),
    );
  }
}

enum _DateFilter { all, thisMonth, lastMonth, custom }

enum _SortOrder { newest, oldest, highest, lowest }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    required this.user,
    required this.authService,
    super.key,
  });

  final AppUser user;
  final AuthService authService;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final TransactionStorage _storage;
  final _searchController = TextEditingController();
  List<ExpenseTransaction> _transactions = [];
  List<RecurringExpense> _recurringExpenses = [];
  int _monthlyBudgetInPaise = 0;
  int _yearlyBudgetInPaise = 0;
  bool _isLoading = true;
  String? _storageError;
  _DateFilter _dateFilter = _DateFilter.all;
  _SortOrder _sortOrder = _SortOrder.newest;
  DateTimeRange? _customRange;

  @override
  void initState() {
    super.initState();
    _storage = TransactionStorage(userId: widget.user.id);
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _storageError = null;
    });
    try {
      final savedTransactions = await _storage.loadTransactions();
      final savedBudget = await _storage.loadMonthlyBudget();
      final savedYearlyBudget = await _storage.loadYearlyBudget();
      final savedRecurringExpenses = await _storage.loadRecurringExpenses();
      final updatedTransactions = List<ExpenseTransaction>.from(
        savedTransactions,
      );
      final updatedRecurringExpenses = _createDueExpenses(
        savedRecurringExpenses,
        updatedTransactions,
      );

      if (updatedTransactions.length != savedTransactions.length) {
        await _storage.saveTransactions(updatedTransactions);
      }
      if (updatedRecurringExpenses.isNotEmpty) {
        await _storage.saveRecurringExpenses(updatedRecurringExpenses);
      }

      if (!mounted) return;
      setState(() {
        _transactions = updatedTransactions;
        _recurringExpenses = updatedRecurringExpenses;
        _monthlyBudgetInPaise = savedBudget;
        _yearlyBudgetInPaise = savedYearlyBudget;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _storageError = 'Could not load saved data: $error';
        _isLoading = false;
      });
    }
  }

  List<RecurringExpense> _createDueExpenses(
    List<RecurringExpense> recurringExpenses,
    List<ExpenseTransaction> transactions,
  ) {
    List<RecurringExpense> updatedExpenses = [];
    DateTime today = DateTime.now();
    bool schedulesChanged = false;

    for (final recurringExpense in recurringExpenses) {
      DateTime nextDueDate = recurringExpense.nextDueDate;

      while (!nextDueDate.isAfter(today)) {
        String transactionId =
            '${recurringExpense.id}_${nextDueDate.year}_'
            '${nextDueDate.month}_${nextDueDate.day}';
        bool transactionAlreadyExists = false;

        for (final transaction in transactions) {
          if (transaction.id == transactionId) {
            transactionAlreadyExists = true;
            break;
          }
        }

        if (!transactionAlreadyExists) {
          transactions.insert(
            0,
            ExpenseTransaction(
              id: transactionId,
              title: recurringExpense.title,
              amountInPaise: recurringExpense.amountInPaise,
              type: TransactionType.expense,
              category: recurringExpense.category,
              date: nextDueDate,
            ),
          );
        }

        nextDueDate = _addMonths(
          nextDueDate,
          recurringExpense.intervalMonths,
          recurringExpense.dayOfMonth,
        );
        schedulesChanged = true;
      }

      updatedExpenses.add(
        RecurringExpense(
          id: recurringExpense.id,
          title: recurringExpense.title,
          amountInPaise: recurringExpense.amountInPaise,
          category: recurringExpense.category,
          nextDueDate: nextDueDate,
          intervalMonths: recurringExpense.intervalMonths,
          dayOfMonth: recurringExpense.dayOfMonth,
        ),
      );
    }

    if (schedulesChanged) {
      return updatedExpenses;
    }
    return recurringExpenses;
  }

  Future<void> _addRecurringExpense() async {
    final recurringExpense = await showDialog<RecurringExpense>(
      context: context,
      builder: (context) => const RecurringExpenseDialog(),
    );
    if (recurringExpense == null || !mounted) return;

    List<RecurringExpense> updatedExpenses = [
      recurringExpense,
      ..._recurringExpenses,
    ];
    List<ExpenseTransaction> updatedTransactions =
        List<ExpenseTransaction>.from(_transactions);
    updatedExpenses = _createDueExpenses(updatedExpenses, updatedTransactions);

    try {
      await _storage.saveTransactions(updatedTransactions);
      await _storage.saveRecurringExpenses(updatedExpenses);
      if (!mounted) return;
      setState(() {
        _transactions = updatedTransactions;
        _recurringExpenses = updatedExpenses;
      });
    } catch (error) {
      _showMessage('Could not save recurring expense: $error');
    }
  }

  Future<void> _deleteRecurringExpense(RecurringExpense expense) async {
    List<RecurringExpense> updatedExpenses = [];
    for (final recurringExpense in _recurringExpenses) {
      if (recurringExpense.id != expense.id) {
        updatedExpenses.add(recurringExpense);
      }
    }

    try {
      await _storage.saveRecurringExpenses(updatedExpenses);
      if (!mounted) return;
      setState(() {
        _recurringExpenses = updatedExpenses;
      });
    } catch (error) {
      _showMessage('Could not remove recurring expense: $error');
    }
  }

  Future<void> _openTransactionForm({ExpenseTransaction? existing}) async {
    final transaction = await showDialog<ExpenseTransaction>(
      context: context,
      builder: (context) => AddTransactionDialog(existing: existing),
    );
    if (transaction == null || !mounted) return;

    final updated = List<ExpenseTransaction>.from(_transactions);
    int index = -1;
    for (int i = 0; i < updated.length; i++) {
      if (updated[i].id == transaction.id) {
        index = i;
        break;
      }
    }
    if (index == -1) {
      updated.insert(0, transaction);
    } else {
      updated[index] = transaction;
    }
    await _saveTransactions(updated);
  }

  Future<void> _saveTransactions(List<ExpenseTransaction> updated) async {
    try {
      await _storage.saveTransactions(updated);
      if (!mounted) return;
      setState(() {
        _transactions = updated;
      });
    } catch (error) {
      _showMessage('Could not save transaction: $error');
    }
  }

  Future<void> _deleteTransaction(ExpenseTransaction transaction) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: Text('Delete "${transaction.title}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final updated = <ExpenseTransaction>[];
    for (final item in _transactions) {
      if (item.id != transaction.id) {
        updated.add(item);
      }
    }
    await _saveTransactions(updated);
  }

  Future<void> _editBudget({required bool yearly}) async {
    int currentBudget = _monthlyBudgetInPaise;
    if (yearly) {
      currentBudget = _yearlyBudgetInPaise;
    }

    final amount = await showDialog<int>(
      context: context,
      builder: (context) => BudgetDialog(
        currentBudgetInPaise: currentBudget,
        title: yearly ? 'Yearly budget' : 'Monthly budget',
      ),
    );
    if (amount == null || !mounted) return;
    try {
      if (yearly) {
        await _storage.saveYearlyBudget(amount);
      } else {
        await _storage.saveMonthlyBudget(amount);
      }
      if (!mounted) return;
      setState(() {
        if (yearly) {
          _yearlyBudgetInPaise = amount;
        } else {
          _monthlyBudgetInPaise = amount;
        }
      });
    } catch (error) {
      String budgetName = yearly ? 'yearly' : 'monthly';
      _showMessage('Could not save $budgetName budget: $error');
    }
  }

  Future<void> _chooseDateFilter(_DateFilter? filter) async {
    if (filter == null) return;
    if (filter == _DateFilter.custom) {
      final now = DateTime.now();
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(now.year + 5),
        initialDateRange: _customRange,
      );
      if (range == null || !mounted) return;
      setState(() {
        _customRange = range;
        _dateFilter = filter;
      });
      return;
    }
    setState(() => _dateFilter = filter);
  }

  Future<void> _exportCsv() async {
    try {
      final file = XFile.fromData(
        Uint8List.fromList(utf8.encode(_transactionsToCsv(_transactions))),
        mimeType: 'text/csv',
        name: 'expense_transactions.csv',
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [file],
          fileNameOverrides: const ['expense_transactions.csv'],
          subject: 'Expense Tracker transactions',
        ),
      );
    } catch (error) {
      _showMessage('Could not export transactions: $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  List<ExpenseTransaction> get _filteredTransactions {
    final now = DateTime.now();
    final query = _searchController.text.trim().toLowerCase();
    final filtered = <ExpenseTransaction>[];

    DateTime lastMonth = DateTime(now.year, now.month - 1);
    DateTime? startDate;
    DateTime? endDate;
    if (_dateFilter == _DateFilter.custom && _customRange != null) {
      startDate = DateTime(
        _customRange!.start.year,
        _customRange!.start.month,
        _customRange!.start.day,
      );
      endDate = DateTime(
        _customRange!.end.year,
        _customRange!.end.month,
        _customRange!.end.day,
        23,
        59,
        59,
        999,
      );
    }

    for (final transaction in _transactions) {
      bool matchesDate = true;
      if (_dateFilter == _DateFilter.thisMonth) {
        matchesDate =
            transaction.date.year == now.year &&
            transaction.date.month == now.month;
      } else if (_dateFilter == _DateFilter.lastMonth) {
        matchesDate =
            transaction.date.year == lastMonth.year &&
            transaction.date.month == lastMonth.month;
      } else if (_dateFilter == _DateFilter.custom &&
          startDate != null &&
          endDate != null) {
        matchesDate =
            !transaction.date.isBefore(startDate) &&
            !transaction.date.isAfter(endDate);
      }

      bool matchesSearch = true;
      if (query.isNotEmpty) {
        matchesSearch =
            transaction.title.toLowerCase().contains(query) ||
            transaction.category.toLowerCase().contains(query) ||
            transaction.type.name.toLowerCase().contains(query);
      }

      if (matchesDate && matchesSearch) {
        filtered.add(transaction);
      }
    }

    if (_sortOrder == _SortOrder.newest) {
      filtered.sort((a, b) => b.date.compareTo(a.date));
    } else if (_sortOrder == _SortOrder.oldest) {
      filtered.sort((a, b) => a.date.compareTo(b.date));
    } else if (_sortOrder == _SortOrder.highest) {
      filtered.sort((a, b) => b.amountInPaise.compareTo(a.amountInPaise));
    } else {
      filtered.sort((a, b) => a.amountInPaise.compareTo(b.amountInPaise));
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    int incomeInPaise = 0;
    int expensesInPaise = 0;
    int monthExpensesInPaise = 0;
    int yearExpensesInPaise = 0;
    DateTime now = DateTime.now();
    for (final transaction in _transactions) {
      if (transaction.type == TransactionType.income) {
        incomeInPaise += transaction.amountInPaise;
      } else {
        expensesInPaise += transaction.amountInPaise;
        if (transaction.date.year == now.year) {
          yearExpensesInPaise += transaction.amountInPaise;
        }
        if (transaction.date.year == now.year &&
            transaction.date.month == now.month) {
          monthExpensesInPaise += transaction.amountInPaise;
        }
      }
    }
    final balanceInPaise = incomeInPaise - expensesInPaise;
    final visibleTransactions = _filteredTransactions;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Dashboard',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Account',
            icon: const Icon(Icons.account_circle_outlined),
            onSelected: (value) async {
              if (value == 'signOut') {
                try {
                  await widget.authService.signOut();
                } catch (error) {
                  _showMessage('Could not sign out: $error');
                }
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                enabled: false,
                child: Text(widget.user.email),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'signOut',
                child: const Text('Sign out'),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Reports',
            onPressed: _isLoading
                ? null
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => ReportsScreen(
                          transactions: List<ExpenseTransaction>.from(
                            _transactions,
                          ),
                          monthlyBudgetInPaise: _monthlyBudgetInPaise,
                          yearlyBudgetInPaise: _yearlyBudgetInPaise,
                        ),
                      ),
                    );
                  },
            icon: const Icon(Icons.bar_chart),
          ),
          IconButton(
            tooltip: 'Export CSV',
            onPressed: _isLoading ? null : _exportCsv,
            icon: const Icon(Icons.ios_share),
          ),
        ],
        toolbarHeight: 68,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _storageError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_storageError!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _loadData,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : _buildDashboard(
              incomeInPaise: incomeInPaise,
              expensesInPaise: expensesInPaise,
              monthExpensesInPaise: monthExpensesInPaise,
              yearExpensesInPaise: yearExpensesInPaise,
              balanceInPaise: balanceInPaise,
              visibleTransactions: visibleTransactions,
            ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add transaction',
        onPressed: _isLoading || _storageError != null
            ? null
            : _openAddTransaction,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _openAddTransaction() {
    _openTransactionForm();
  }

  Widget _buildDashboard({
    required int incomeInPaise,
    required int expensesInPaise,
    required int monthExpensesInPaise,
    required int yearExpensesInPaise,
    required int balanceInPaise,
    required List<ExpenseTransaction> visibleTransactions,
  }) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    final name = widget.user.email
        .split('@')
        .first
        .replaceAll(RegExp(r'[._-]+'), ' ')
        .trim();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isEmpty ? greeting : '$greeting, $name',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: const Color(0xFF18312C),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "Here's your financial overview.",
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: const Color(0xFF687A74)),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF176D5A), Color(0xFF104C43)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22104C43),
                      blurRadius: 20,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Total balance',
                            style: TextStyle(
                              color: Color(0xFFD1E7DF),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.account_balance_wallet_outlined,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '₹ ${_formatCurrency(balanceInPaise, includePaise: true)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Your available balance',
                      style: TextStyle(color: Color(0xFFD1E7DF)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: SummaryCard(
                      title: 'Income',
                      amount: '₹ ${_formatCurrency(incomeInPaise)}',
                      icon: Icons.south_west,
                      color: const Color(0xFF147D64),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SummaryCard(
                      title: 'Expenses',
                      amount: '₹ ${_formatCurrency(expensesInPaise)}',
                      icon: Icons.north_east,
                      color: const Color(0xFFD97736),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildBudgetCard(
                title: 'Monthly budget',
                spentInPaise: monthExpensesInPaise,
                budgetInPaise: _monthlyBudgetInPaise,
                onEdit: () {
                  _editBudget(yearly: false);
                },
              ),
              const SizedBox(height: 12),
              _buildBudgetCard(
                title: 'Yearly budget',
                spentInPaise: yearExpensesInPaise,
                budgetInPaise: _yearlyBudgetInPaise,
                onEdit: () {
                  _editBudget(yearly: true);
                },
              ),
              const SizedBox(height: 12),
              _buildRecurringExpensesCard(),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Recent Transactions',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: const Color(0xFF18312C),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${visibleTransactions.length} shown',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: const Color(0xFF687A74)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search description, category, or type',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.clear),
                        ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<_DateFilter>(
                      initialValue: _dateFilter,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Date',
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: _DateFilter.all,
                          child: Text('All time'),
                        ),
                        DropdownMenuItem(
                          value: _DateFilter.thisMonth,
                          child: Text('This month'),
                        ),
                        DropdownMenuItem(
                          value: _DateFilter.lastMonth,
                          child: Text('Last month'),
                        ),
                        DropdownMenuItem(
                          value: _DateFilter.custom,
                          child: Text(
                            'Custom range',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      onChanged: _chooseDateFilter,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<_SortOrder>(
                      initialValue: _sortOrder,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Sort',
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: _SortOrder.newest,
                          child: Text('Newest'),
                        ),
                        DropdownMenuItem(
                          value: _SortOrder.oldest,
                          child: Text('Oldest'),
                        ),
                        DropdownMenuItem(
                          value: _SortOrder.highest,
                          child: Text(
                            'Highest amount',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: _SortOrder.lowest,
                          child: Text(
                            'Lowest amount',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _sortOrder = value);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (visibleTransactions.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              _transactions.isEmpty
                                  ? Icons.receipt_long_outlined
                                  : Icons.search_off,
                              size: 36,
                              color: const Color(0xFF82918B),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _transactions.isEmpty
                                  ? 'No transactions yet. Tap + to add one.'
                                  : 'No transactions match these filters.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Color(0xFF687A74)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: visibleTransactions.length,
                  itemBuilder: (context, index) {
                    final transaction = visibleTransactions[index];
                    return TransactionTile(
                      transaction: transaction,
                      onEdit: () {
                        _openTransactionForm(existing: transaction);
                      },
                      onDelete: () {
                        _deleteTransaction(transaction);
                      },
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBudgetCard({
    required String title,
    required int spentInPaise,
    required int budgetInPaise,
    required VoidCallback onEdit,
  }) {
    double progress = 0;
    if (budgetInPaise > 0) {
      progress = spentInPaise / budgetInPaise;
      if (progress > 1) {
        progress = 1;
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onEdit,
                  child: Text(budgetInPaise == 0 ? 'Set $title' : 'Edit'),
                ),
              ],
            ),
            Text(
              budgetInPaise == 0
                  ? 'No budget set'
                  : '₹ ${_formatCurrency(spentInPaise)} of '
                        '₹ ${_formatCurrency(budgetInPaise)} used',
            ),
            if (budgetInPaise > 0) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: progress,
                color: spentInPaise > budgetInPaise ? Colors.red : Colors.teal,
                minHeight: 8,
              ),
              const SizedBox(height: 6),
              Text(
                spentInPaise > budgetInPaise
                    ? 'Over budget by ₹ ${_formatCurrency(spentInPaise - budgetInPaise)}'
                    : '₹ ${_formatCurrency(budgetInPaise - spentInPaise)} remaining',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecurringExpensesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Recurring expenses',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton.icon(
                  onPressed: _addRecurringExpense,
                  icon: const Icon(Icons.repeat),
                  label: const Text('Add'),
                ),
              ],
            ),
            if (_recurringExpenses.isEmpty)
              const Text('No recurring expenses set up.')
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _recurringExpenses.length,
                itemBuilder: (context, index) {
                  final expense = _recurringExpenses[index];
                  String repeat = 'Monthly';
                  if (expense.intervalMonths == 12) {
                    repeat = 'Yearly';
                  }
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(expense.title),
                    subtitle: Text(
                      '${expense.category} • $repeat • '
                      'Next: ${_formatDate(expense.nextDueDate)}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('₹ ${_formatCurrency(expense.amountInPaise)}'),
                        IconButton(
                          tooltip: 'Remove recurring expense',
                          onPressed: () {
                            _deleteRecurringExpense(expense);
                          },
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class SummaryCard extends StatelessWidget {
  final String title;
  final String amount;
  final IconData icon;
  final Color color;

  const SummaryCard({
    super.key,
    required this.title,
    required this.amount,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF687A74),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                amount,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TransactionTile extends StatelessWidget {
  final ExpenseTransaction transaction;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const TransactionTile({
    super.key,
    required this.transaction,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isIncome = transaction.type == TransactionType.income;
    final accentColor = isIncome
        ? const Color(0xFF147D64)
        : const Color(0xFFD97736);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 14, right: 4),
        minVerticalPadding: 12,
        onTap: onEdit,
        leading: CircleAvatar(
          backgroundColor: accentColor.withValues(alpha: 0.12),
          foregroundColor: accentColor,
          child: Icon(
            isIncome ? Icons.south_west : Icons.receipt_long_outlined,
          ),
        ),
        title: Text(
          transaction.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${transaction.category} • ${_formatDate(transaction.date)}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${isIncome ? '+' : '-'} ₹ ${_formatCurrency(transaction.amountInPaise)}',
              style: TextStyle(fontWeight: FontWeight.w700, color: accentColor),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: 'Transaction actions',
              onSelected: (action) {
                if (action == 'edit') onEdit();
                if (action == 'delete') onDelete();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ReportsScreen extends StatefulWidget {
  final List<ExpenseTransaction> transactions;
  final int monthlyBudgetInPaise;
  final int yearlyBudgetInPaise;

  const ReportsScreen({
    super.key,
    required this.transactions,
    required this.monthlyBudgetInPaise,
    required this.yearlyBudgetInPaise,
  });

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    int monthIncome = 0;
    int monthExpenses = 0;
    Map<String, int> categoryTotals = {};

    for (final transaction in widget.transactions) {
      if (transaction.date.year == now.year &&
          transaction.date.month == now.month) {
        if (transaction.type == TransactionType.income) {
          monthIncome += transaction.amountInPaise;
        } else {
          monthExpenses += transaction.amountInPaise;
          if (categoryTotals.containsKey(transaction.category)) {
            categoryTotals[transaction.category] =
                categoryTotals[transaction.category]! +
                transaction.amountInPaise;
          } else {
            categoryTotals[transaction.category] = transaction.amountInPaise;
          }
        }
      }
    }

    List<String> categories = categoryTotals.keys.toList();
    categories.sort((firstCategory, secondCategory) {
      return categoryTotals[secondCategory]!.compareTo(
        categoryTotals[firstCategory]!,
      );
    });

    List<Widget> categoryWidgets = [];
    for (String category in categories) {
      int amount = categoryTotals[category]!;
      double percent = 0;
      if (monthExpenses > 0) {
        percent = amount / monthExpenses;
      }

      categoryWidgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(category)),
                  Text('₹ ${_formatCurrency(amount)}'),
                ],
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: percent, minHeight: 8),
              const SizedBox(height: 3),
              Text('${(percent * 100).round()}% of monthly expenses'),
            ],
          ),
        ),
      );
    }

    final yearExpenses = _yearExpenses(widget.transactions, now.year);

    return Scaffold(
      appBar: AppBar(title: const Text('Monthly report')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            '${_monthName(now.month)} ${now.year}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          SummaryCard(
            title: 'Income this month',
            amount: '₹ ${_formatCurrency(monthIncome)}',
            icon: Icons.arrow_downward,
            color: Colors.green,
          ),
          SummaryCard(
            title: 'Expenses this month',
            amount: '₹ ${_formatCurrency(monthExpenses)}',
            icon: Icons.arrow_upward,
            color: Colors.orange,
          ),
          const SizedBox(height: 24),
          BudgetOverviewCard(
            monthlyBudgetInPaise: widget.monthlyBudgetInPaise,
            yearlyBudgetInPaise: widget.yearlyBudgetInPaise,
            monthlySpentInPaise: monthExpenses,
            yearlySpentInPaise: yearExpenses,
            formatCurrency: _formatCurrency,
          ),
          const SizedBox(height: 24),
          const Text(
            'Expenses by category',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (categoryWidgets.isEmpty)
            const Text('No expenses recorded this month.')
          else
            Column(children: categoryWidgets),
        ],
      ),
    );
  }

  int _yearExpenses(List<ExpenseTransaction> transactions, int year) {
    var total = 0;
    for (final transaction in transactions) {
      if (transaction.type == TransactionType.expense &&
          transaction.date.year == year) {
        total += transaction.amountInPaise;
      }
    }
    return total;
  }

}

DateTime _addMonths(DateTime date, int months, int dayOfMonth) {
  DateTime firstDayOfNewMonth = DateTime(date.year, date.month + months, 1);
  int lastDayOfNewMonth = DateTime(
    firstDayOfNewMonth.year,
    firstDayOfNewMonth.month + 1,
    0,
  ).day;
  int day = dayOfMonth;
  if (day > lastDayOfNewMonth) {
    day = lastDayOfNewMonth;
  }

  return DateTime(
    firstDayOfNewMonth.year,
    firstDayOfNewMonth.month,
    day,
    date.hour,
    date.minute,
    date.second,
  );
}

String _amountInputValue(int amountInPaise) {
  return app_formatters.amountInputValue(amountInPaise);
}

String _formatDate(DateTime date) {
  return app_formatters.formatDate(date);
}

String _monthName(int month) {
  List<String> months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return months[month - 1];
}

String _transactionsToCsv(List<ExpenseTransaction> transactions) {
  String escape(String value) {
    final safeValue = RegExp(r'^\s*[=+\-@]').hasMatch(value)
        ? "'$value"
        : value;
    return '"${safeValue.replaceAll('"', '""')}"';
  }

  String csv = 'Date,Type,Category,Description,Amount (INR)\r\n';
  for (final transaction in transactions) {
    csv += '${escape(_formatDate(transaction.date))},';
    csv += '${escape(transaction.type.name)},';
    csv += '${escape(transaction.category)},';
    csv += '${escape(transaction.title)},';
    csv += '${_amountInputValue(transaction.amountInPaise)}\r\n';
  }
  return csv;
}

String _formatCurrency(int amountInPaise, {bool includePaise = false}) {
  final absoluteAmount = amountInPaise.abs();
  final digits = (absoluteAmount ~/ 100).toString();
  final showPaise = includePaise || absoluteAmount % 100 != 0;
  final sign = amountInPaise < 0 ? '-' : '';
  String formatted;
  if (digits.length <= 3) {
    formatted = digits;
  } else {
    final leadingDigits = digits.substring(0, digits.length - 3);
    final groupedLeading = StringBuffer();
    final firstGroupLength = leadingDigits.length % 2 == 0 ? 2 : 1;
    groupedLeading.write(leadingDigits.substring(0, firstGroupLength));
    for (
      var index = firstGroupLength;
      index < leadingDigits.length;
      index += 2
    ) {
      groupedLeading
        ..write(',')
        ..write(leadingDigits.substring(index, index + 2));
    }
    formatted = '$groupedLeading,${digits.substring(digits.length - 3)}';
  }
  return '$sign$formatted${showPaise ? '.${(absoluteAmount % 100).toString().padLeft(2, '0')}' : ''}';
}

// Flutter Widget Preview
@Preview(name: 'Local sign in', group: 'Expense Tracker')
Widget expenseTrackerPreview() {
  return MaterialApp(home: SignInScreen(authService: LocalAuthService()));
}
