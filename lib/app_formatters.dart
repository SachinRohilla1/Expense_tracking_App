String amountInputValue(int amountInPaise) {
  final absolute = amountInPaise.abs();
  return '${absolute ~/ 100}.${(absolute % 100).toString().padLeft(2, '0')}';
}

String formatDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}

int? parseAmountInPaise(String value) {
  final parts = value.trim().split('.');
  final rupees = int.tryParse(parts[0]);
  if (rupees == null) return null;
  final paise = parts.length == 1 ? 0 : int.tryParse(parts[1].padRight(2, '0'));
  if (paise == null) return null;
  return rupees * 100 + paise;
}
