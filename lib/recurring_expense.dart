class RecurringExpense {
  final String id;
  final String title;
  final int amountInPaise;
  final String category;
  final DateTime nextDueDate;
  final int intervalMonths;
  final int dayOfMonth;

  const RecurringExpense({
    required this.id,
    required this.title,
    required this.amountInPaise,
    required this.category,
    required this.nextDueDate,
    required this.intervalMonths,
    required this.dayOfMonth,
  });

  Map<String, Object> toJson() {
    return {
      'id': id,
      'title': title,
      'amountInPaise': amountInPaise,
      'category': category,
      'nextDueDate': nextDueDate.toIso8601String(),
      'intervalMonths': intervalMonths,
      'dayOfMonth': dayOfMonth,
    };
  }

  factory RecurringExpense.fromJson(Map<String, dynamic> json) {
    return RecurringExpense(
      id: json['id'] as String,
      title: json['title'] as String,
      amountInPaise: json['amountInPaise'] as int,
      category: json['category'] as String,
      nextDueDate: DateTime.parse(json['nextDueDate'] as String),
      intervalMonths: json['intervalMonths'] as int,
      dayOfMonth: json['dayOfMonth'] as int,
    );
  }
}
