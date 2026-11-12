import 'package:flutter/material.dart';

import 'app_formatters.dart';
import 'expense_transaction.dart';
import 'recurring_expense.dart';

const _categories = [
  'Food',
  'Transport',
  'Shopping',
  'Bills',
  'Health',
  'Entertainment',
  'Salary',
  'Business',
  'Other',
];

class RecurringExpenseDialog extends StatefulWidget {
  const RecurringExpenseDialog({super.key});

  @override
  State<RecurringExpenseDialog> createState() => _RecurringExpenseDialogState();
}

class _RecurringExpenseDialogState extends State<RecurringExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  String _category = _categories.first;
  int _intervalMonths = 1;
  DateTime _nextDueDate = DateTime.now();

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.pop(
      context,
      RecurringExpense(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: _titleController.text.trim(),
        amountInPaise: parseAmountInPaise(_amountController.text)!,
        category: _category,
        nextDueDate: _nextDueDate,
        intervalMonths: _intervalMonths,
        dayOfMonth: _nextDueDate.day,
      ),
    );
  }

  Future<void> _selectFirstDueDate() async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _nextDueDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );

    if (selectedDate != null) {
      setState(() {
        _nextDueDate = selectedDate;
      });
    }
  }

  List<DropdownMenuItem<String>> _categoryItems() {
    return [
      for (final category in _categories)
        DropdownMenuItem(value: category, child: Text(category)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add recurring expense'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Description'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter a description';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₹ ',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (value) {
                  final amount = value?.trim() ?? '';
                  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(amount) ||
                      (parseAmountInPaise(amount) ?? 0) <= 0) {
                    return 'Enter an amount greater than zero';
                  }
                  return null;
                },
              ),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: _categoryItems(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _category = value;
                    });
                  }
                },
              ),
              DropdownButtonFormField<int>(
                initialValue: _intervalMonths,
                decoration: const InputDecoration(labelText: 'Repeat'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('Every month')),
                  DropdownMenuItem(value: 12, child: Text('Every year')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _intervalMonths = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _selectFirstDueDate,
                icon: const Icon(Icons.calendar_today),
                label: Text('First due: ${formatDate(_nextDueDate)}'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class AddTransactionDialog extends StatefulWidget {
  final ExpenseTransaction? existing;

  const AddTransactionDialog({super.key, this.existing});

  @override
  State<AddTransactionDialog> createState() => _AddTransactionDialogState();
}

class _AddTransactionDialogState extends State<AddTransactionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _amountController;
  late TransactionType _type;
  late String _category;
  late DateTime _date;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _titleController = TextEditingController(text: existing?.title ?? '');
    _amountController = TextEditingController(
      text: existing == null ? '' : amountInputValue(existing.amountInPaise),
    );
    _type = existing?.type ?? TransactionType.expense;
    _category = existing?.category ?? _categories.first;
    if (!_categories.contains(_category)) _category = 'Other';
    _date = existing?.date ?? DateTime.now();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final existing = widget.existing;
    Navigator.of(context).pop(
      ExpenseTransaction(
        id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        title: _titleController.text.trim(),
        amountInPaise: parseAmountInPaise(_amountController.text)!,
        type: _type,
        category: _category,
        date: _date,
      ),
    );
  }

  Future<void> _selectDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (selected != null) setState(() => _date = selected);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Edit transaction' : 'Add transaction'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<TransactionType>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(
                    value: TransactionType.expense,
                    child: Text('Expense'),
                  ),
                  DropdownMenuItem(
                    value: TransactionType.income,
                    child: Text('Income'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _type = value);
                },
              ),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  for (final category in _categories)
                    DropdownMenuItem(value: category, child: Text(category)),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _category = value;
                    });
                  }
                },
              ),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Description'),
                textCapitalization: TextCapitalization.sentences,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter a description';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₹ ',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (value) {
                  final amount = value?.trim() ?? '';
                  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(amount)) {
                    return 'Enter a valid amount (up to 2 decimals)';
                  }
                  if (parseAmountInPaise(amount) == 0) {
                    return 'Amount must be greater than zero';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _selectDate,
                  icon: const Icon(Icons.calendar_today),
                  label: Text('Date: ${formatDate(_date)}'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(_isEditing ? 'Save changes' : 'Save'),
        ),
      ],
    );
  }
}

class BudgetDialog extends StatefulWidget {
  final int currentBudgetInPaise;
  final String title;

  const BudgetDialog({
    super.key,
    required this.currentBudgetInPaise,
    required this.title,
  });

  @override
  State<BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<BudgetDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.currentBudgetInPaise == 0
          ? ''
          : amountInputValue(widget.currentBudgetInPaise),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Budget amount',
            prefixText: '₹ ',
          ),
          validator: (value) {
            final amount = value?.trim() ?? '';
            if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(amount) ||
                (parseAmountInPaise(amount) ?? 0) <= 0) {
              return 'Enter a valid amount greater than zero';
            }
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, parseAmountInPaise(_controller.text)!);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
