import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as excel;

import 'file_download.dart';

/// Exports tabular report data with the packages the project already uses
/// (csv, excel). Works on web (browser download) and other platforms.
class TableExport {
  TableExport._();

  static String _stamp() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}';
  }

  static String _cell(Object? value) {
    if (value == null) return '';
    if (value is DateTime) return value.toLocal().toIso8601String();
    return value.toString();
  }

  /// Returns true when the file was handed to the browser / saved.
  static Future<bool> csvFile({
    required String baseName,
    required List<String> headers,
    required List<List<Object?>> rows,
  }) {
    final content = const ListToCsvConverter().convert([
      headers,
      for (final row in rows) row.map(_cell).toList(),
    ]);

    // UTF-8 BOM so Excel opens non-ASCII text correctly.
    final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(content)]);

    return saveBytesAsFile(
      fileName: '${baseName}_${_stamp()}.csv',
      bytes: bytes,
      mimeType: 'text/csv;charset=utf-8',
      dialogTitle: 'Export CSV',
    );
  }

  static Future<bool> excelFile({
    required String baseName,
    required String sheetName,
    required List<String> headers,
    required List<List<Object?>> rows,
  }) {
    final workbook = excel.Excel.createExcel();
    final defaultSheet = workbook.getDefaultSheet() ?? 'Sheet1';

    workbook.rename(defaultSheet, sheetName);

    final sheet = workbook[sheetName];

    sheet.appendRow([for (final h in headers) excel.TextCellValue(h)]);

    for (final row in rows) {
      sheet.appendRow([
        for (final value in row)
          value is int
              ? excel.IntCellValue(value)
              : value is double
              ? excel.DoubleCellValue(value)
              : excel.TextCellValue(_cell(value)),
      ]);
    }

    final encoded = workbook.encode();

    if (encoded == null || encoded.isEmpty) {
      throw Exception('Could not generate the Excel file.');
    }

    return saveBytesAsFile(
      fileName: '${baseName}_${_stamp()}.xlsx',
      bytes: Uint8List.fromList(encoded),
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      dialogTitle: 'Export Excel',
    );
  }
}
