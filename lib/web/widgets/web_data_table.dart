import 'package:flutter/material.dart';

import '../../core/shared/widgets/app_states.dart';
import '../../core/theme/colors.dart';

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

  // The sorted copy is kept between builds. Sorting is the most expensive
  // thing this widget does, and paging, changing the page size, hovering a
  // row or any unrelated rebuild of the page above used to pay for a full
  // copy-and-sort of every record. The cache is dropped the moment a new row
  // list arrives, so what is drawn is never stale.
  List<T>? _cachedSorted;

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

    // Any new list may hold different records even at the same length, so
    // only the very same instance keeps the cached order.
    if (!identical(oldWidget.rows, widget.rows) ||
        !identical(oldWidget.columns, widget.columns)) {
      _cachedSorted = null;
    }
  }

  void _sortBy(int column, bool ascending) {
    setState(() {
      _sortColumn = column;
      _ascending = ascending;
      _cachedSorted = null;
    });
  }

  List<T> get _sortedRows {
    final cached = _cachedSorted;
    if (cached != null) return cached;

    final rows = List<T>.from(widget.rows);
    final index = _sortColumn;

    if (index == null || index >= widget.columns.length) {
      return _cachedSorted = rows;
    }

    final sortValue = widget.columns[index].sortValue;

    if (sortValue == null) {
      return _cachedSorted = rows;
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

    return _cachedSorted = rows;
  }

  /// Row background for pointer and keyboard states.
  ///
  /// Hover answers the pointer, which web users expect of anything clickable.
  /// Focus is drawn stronger and on its own, because a keyboard user has no
  /// cursor to tell them which row Enter would open.
  WidgetStateProperty<Color?> _rowColor(ColorScheme colors) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused)) {
        return colors.primary.withValues(alpha: 0.12);
      }

      if (states.contains(WidgetState.hovered)) {
        return colors.primary.withValues(alpha: 0.04);
      }

      return null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final rows = _sortedRows;

    // One resolver for the whole table instead of one per row.
    final rowColor = _rowColor(colors);

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
              // Crossfaded so a filter that empties the table reads as the
              // rows leaving rather than as the card snapping shut.
              return AppStateSwitcher(
                child: rows.isEmpty
                    ? AppEmptyState(
                        key: const ValueKey('empty'),
                        icon: Icons.inbox_outlined,
                        // Same sentence the pages already pass in, so "no
                        // matches" never reads as "could not load".
                        title: widget.emptyMessage,
                        compact: true,
                      )
                    : Scrollbar(
                        key: const ValueKey('rows'),
                        controller: _horizontal,
                        thumbVisibility: true,
                        notificationPredicate: (n) => n.depth == 0,
                        child: SingleChildScrollView(
                          controller: _horizontal,
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: constraints.maxWidth,
                            ),
                            // Scrolling a wide table sideways repaints only
                            // the table, not the page and charts behind it.
                            child: RepaintBoundary(
                              child: DataTable(
                                // Heading, row heights and text styles come
                                // from the shared DataTableThemeData
                                // (app_theme.dart).
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
                                          minWidth:
                                              widget.columns[i].minWidth ?? 0,
                                        ),
                                        child: Text(widget.columns[i].label),
                                      ),
                                      onSort: widget.columns[i].sortValue == null
                                          ? null
                                          : _sortBy,
                                    ),
                                  if (widget.actions != null)
                                    const DataColumn(label: Text('Actions')),
                                ],
                                rows: [
                                  for (final row in pageRows)
                                    DataRow(
                                      color: rowColor,
                                      onSelectChanged: widget.onRowTap == null
                                          ? null
                                          : (_) => widget.onRowTap!(row),
                                      cells: [
                                        for (final column in widget.columns)
                                          DataCell(
                                            // Chips, menus and tinted cells
                                            // keep their own paint layer, so
                                            // pointing at a row repaints the
                                            // row tint and nothing else.
                                            RepaintBoundary(
                                              child: column.cell(row),
                                            ),
                                          ),
                                        if (widget.actions != null)
                                          DataCell(
                                            RepaintBoundary(
                                              child: widget.actions!(row),
                                            ),
                                          ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
              );
            },
          ),
          Divider(height: 1, color: colors.outlineVariant),
          Container(
            color: colors.surfaceContainerLow,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: 6,
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.xs,
              children: [
                Text(
                  '${rows.length} record${rows.length == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant),
                ),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.lg,
                  runSpacing: AppSpacing.xs,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Rows per page',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        DropdownButton<int>(
                          value: _rowsPerPage,
                          underline: const SizedBox.shrink(),
                          isDense: true,
                          items: [
                            for (final option in widget.rowsPerPageOptions)
                              DropdownMenuItem(
                                value: option,
                                child: Text('$option'),
                              ),
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
                          onPressed: _page > 0
                              ? () => setState(() => _page--)
                              : null,
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
