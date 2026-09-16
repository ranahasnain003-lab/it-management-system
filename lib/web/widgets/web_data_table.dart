import 'package:flutter/material.dart';

/// Column definition for [WebDataTable].
class WebColumn<T> {
  const WebColumn({
    required this.label,
    required this.cell,
    this.sortValue,
    this.numeric = false,
    this.minWidth,
  });

  final String label;

  /// Builds the cell content for a row.
  final Widget Function(T row) cell;

  /// Value used for sorting. Columns without it are not sortable.
  final Comparable<Object?>? Function(T row)? sortValue;

  final bool numeric;

  /// Optional minimum width hint for text-heavy columns.
  final double? minWidth;
}

/// Desktop data table: sortable columns, client-side pagination, horizontal
/// scrolling on narrow widths, optional row tap and trailing actions.
///
/// Data comes from the app's existing providers/streams; filtering and search
/// are applied by the page before rows are handed to the table.
class WebDataTable<T> extends StatefulWidget {
  const WebDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.onRowTap,
    this.actions,
    this.initialSortColumn,
    this.initialSortAscending = true,
    this.rowsPerPageOptions = const [10, 25, 50, 100],
    this.initialRowsPerPage = 25,
    this.emptyMessage = 'No records found.',
  });

  final List<WebColumn<T>> columns;
  final List<T> rows;
  final void Function(T row)? onRowTap;
  final Widget Function(T row)? actions;
  final int? initialSortColumn;
  final bool initialSortAscending;
  final List<int> rowsPerPageOptions;
  final int initialRowsPerPage;
  final String emptyMessage;

  @override
  State<WebDataTable<T>> createState() => _WebDataTableState<T>();
}

class _WebDataTableState<T> extends State<WebDataTable<T>> {
  // Explicit controller: on desktop a Scrollbar without one falls back to the
  // (vertical) PrimaryScrollController and throws for this horizontal view.
  final ScrollController _horizontal = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  int? _sortColumn;
  late bool _ascending;
  late int _rowsPerPage;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _sortColumn = widget.initialSortColumn;
    _ascending = widget.initialSortAscending;
    _rowsPerPage = widget.initialRowsPerPage;
  }

  @override
  void didUpdateWidget(covariant WebDataTable<T> oldWidget) {
    super.didUpdateWidget(oldWidget);

    // A different result set (search or filter changed) starts at page 1,
    // so the best matches are never hidden on a later page.
    if (oldWidget.rows.length != widget.rows.length) {
      _page = 0;
    }
  }

  List<T> get _sortedRows {
    final rows = List<T>.from(widget.rows);
    final index = _sortColumn;

    if (index == null || index >= widget.columns.length) {
      return rows;
    }

    final sortValue = widget.columns[index].sortValue;

    if (sortValue == null) {
      return rows;
    }

    rows.sort((a, b) {
      final av = sortValue(a);
      final bv = sortValue(b);

      if (av == null && bv == null) return 0;
      if (av == null) return 1;
      if (bv == null) return -1;

      final result = av.compareTo(bv);
      return _ascending ? result : -result;
    });

    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final rows = _sortedRows;

    final pageCount = rows.isEmpty ? 1 : (rows.length / _rowsPerPage).ceil();

    // Keep the current page valid when filters shrink the data.
    if (_page >= pageCount) {
      _page = pageCount - 1;
    }

    final start = _page * _rowsPerPage;
    final end = (start + _rowsPerPage).clamp(0, rows.length);
    final pageRows = rows.isEmpty ? <T>[] : rows.sublist(start, end);

    return Card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (rows.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 52, horizontal: 24),
                  child: Column(
                    children: [
                      Icon(Icons.inbox_outlined, size: 40, color: colors.onSurfaceVariant.withValues(alpha: 0.6)),
                      const SizedBox(height: 10),
                      Text(
                        widget.emptyMessage,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.onSurfaceVariant, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                );
              }

              return Scrollbar(
                controller: _horizontal,
                thumbVisibility: true,
                notificationPredicate: (n) => n.depth == 0,
                child: SingleChildScrollView(
                  controller: _horizontal,
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: DataTable(
                      // Heading, row heights and text styles come from the
                      // shared DataTableThemeData (app_theme.dart).
                      showCheckboxColumn: false,
                      dividerThickness: 1,
                      sortColumnIndex: _sortColumn,
                      sortAscending: _ascending,
                      columns: [
                        for (var i = 0; i < widget.columns.length; i++)
                          DataColumn(
                            numeric: widget.columns[i].numeric,
                            label: ConstrainedBox(
                              constraints: BoxConstraints(
                                minWidth: widget.columns[i].minWidth ?? 0,
                              ),
                              child: Text(widget.columns[i].label),
                            ),
                            onSort: widget.columns[i].sortValue == null
                                ? null
                                : (column, ascending) {
                                    setState(() {
                                      _sortColumn = column;
                                      _ascending = ascending;
                                    });
                                  },
                          ),
                        if (widget.actions != null)
                          const DataColumn(label: Text('Actions')),
                      ],
                      rows: [
                        for (final row in pageRows)
                          DataRow(
                            color: WidgetStateProperty.resolveWith(
                              (states) => states.contains(WidgetState.hovered)
                                  ? colors.primary.withValues(alpha: 0.04)
                                  : null,
                            ),
                            onSelectChanged: widget.onRowTap == null
                                ? null
                                : (_) => widget.onRowTap!(row),
                            cells: [
                              for (final column in widget.columns)
                                DataCell(column.cell(row)),
                              if (widget.actions != null)
                                DataCell(widget.actions!(row)),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          Divider(height: 1, color: colors.outlineVariant),
          Container(
            color: colors.surfaceContainerLow,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 4,
              children: [
                Text(
                  '${rows.length} record${rows.length == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant),
                ),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16,
                  children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Rows per page',
                      style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: _rowsPerPage,
                      underline: const SizedBox.shrink(),
                      isDense: true,
                      items: [
                        for (final option in widget.rowsPerPageOptions)
                          DropdownMenuItem(value: option, child: Text('$option')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _rowsPerPage = value;
                          _page = 0;
                        });
                      },
                    ),
                  ],
                ),
                Text(
                  rows.isEmpty
                      ? '0 of 0'
                      : '${start + 1}–$end of ${rows.length}',
                  style: TextStyle(fontSize: 12.5, color: colors.onSurface),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Previous page',
                      onPressed: _page > 0 ? () => setState(() => _page--) : null,
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    IconButton(
                      tooltip: 'Next page',
                      onPressed: _page < pageCount - 1
                          ? () => setState(() => _page++)
                          : null,
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
