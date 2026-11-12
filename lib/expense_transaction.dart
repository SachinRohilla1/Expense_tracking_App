enum TransactionType { income, expense }

class ExpenseTransaction {
  final String id;
  final String title;
  final int amountInPaise;
  final TransactionType type;
  final String category;
  final DateTime date;

  const ExpenseTransaction({
    required this.id,
    required this.title,
    required this.amountInPaise,
    required this.type,
    required this.category,
    required this.date,
  });

  Map<String, Object> toJson() {
    return {
      'id': id,
      'title': title,
      'amountInPaise': amountInPaise,
      'type': type.name,
      'category': category,
      'date': date.toIso8601String(),
    };
  }

  factory ExpenseTransaction.fromJson(Map<String, dynamic> json) {
    TransactionType transactionType = TransactionType.expense;
    if (json['type'] == 'income') {
      transactionType = TransactionType.income;
    }

    return ExpenseTransaction(
      id: json['id'] as String,
      title: json['title'] as String,
      amountInPaise: json['amountInPaise'] as int,
      type: transactionType,
      category: json['category'] as String,
      date: DateTime.parse(json['date'] as String),
    );
  }
}
