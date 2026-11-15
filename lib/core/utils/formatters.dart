import 'package:intl/intl.dart';

/// Display formatting for amounts, durations and percentages.
abstract final class Formatters {
  static final NumberFormat _amount = NumberFormat('#,##0.##', 'en_US');

  /// `AED 1,250` / `AED 45.5`
  static String aed(double amount) => 'AED ${_amount.format(amount)}';

  /// `45 min`, `2 h`, `2 h 30 min`
  static String duration(int minutes) {
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '$hours h' : '$hours h $rest min';
  }

  /// `20%`, `12.5%`
  static String percent(double value) => '${_amount.format(value)}%';
}
