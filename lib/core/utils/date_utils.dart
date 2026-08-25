import 'package:intl/intl.dart';

class DateUtilsHelper {
  static String formatDate(DateTime date) {
    return DateFormat('dd MMM yyyy').format(date);
  }


  static String formatDateTime(DateTime date) {
    return DateFormat('dd MMM yyyy, hh:mm a').format(date);
  }


  static String formatTime(DateTime date) {
    return DateFormat('hh:mm a').format(date);
  }


  static String formatMonth(DateTime date) {
    return DateFormat('MMMM yyyy').format(date);
  }
}