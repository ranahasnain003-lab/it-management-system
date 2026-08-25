import 'package:intl/intl.dart';

class Formatter {

  static String currency(double amount) {
    final format = NumberFormat.currency(
      symbol: 'Rs ',
      decimalDigits: 2,
    );

    return format.format(amount);
  }


  static String number(int value) {
    final format = NumberFormat('#,###');

    return format.format(value);
  }


  static String decimal(double value) {
    final format = NumberFormat('#,##0.00');

    return format.format(value);
  }


  static String capitalize(String text) {
    if (text.isEmpty) {
      return text;
    }

    return text[0].toUpperCase() +
        text.substring(1).toLowerCase();
  }
}