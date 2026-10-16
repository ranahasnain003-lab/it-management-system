/// A picker that can be searched.
///
/// A `DropdownButtonFormField` is fine for four options and unusable for
/// forty: the menu is a plain scrolling list with no way to type, so choosing
/// a Bazaar meant scrolling past every other Bazaar to find it. This is the
/// same control with a search field on top.
///
/// It is a drop-in replacement for the way this app used that dropdown - same
/// [InputDecoration], same `validator`, same `onChanged`, same disabled
/// behaviour - so swapping one in changes how a value is chosen and nothing
/// about what the form then does with it.
///
/// The options open in a bottom sheet on a phone and a dialog on a wide
/// window, because a sheet pinned to the bottom of a 1440px browser window
/// would put the list a long way from the field it belongs to.
library;

import 'package:flutter/material.dart';

import '../../theme/colors.dart';

/// One choice in a [SearchablePickerField].
@immutable
class PickerOption<T> {
  const PickerOption({
    required this.value,
    required this.label,
    this.subtitle,
    this.icon,
    this.keywords,
  });

  /// What [SearchablePickerField.onChanged] reports when this is chosen.
  final T value;

  /// The line shown in the field and in the list.
  final String label;

  /// A quieter second line - a Bazaar's city, an asset's tag.
  final String? subtitle;

  final IconData? icon;

  /// Extra words this option should be findable by but which are not shown,
  /// such as an asset id somebody might type from a sticker.
  final String? keywords;

  /// Everything a search looks at, folded to lower case once.
  String get haystack =>
      '$label ${subtitle ?? ''} ${keywords ?? ''}'.toLowerCase();
}

/// A form field that opens a searchable list of [options].
class SearchablePickerField<T> extends FormField<T> {
  SearchablePickerField({
    super.key,
    required List<PickerOption<T>> options,
    required InputDecoration decoration,
    required ValueChanged<T?> onChanged,
    T? value,
    super.validator,
    super.enabled,
    String searchHint = 'Search…',
    String emptyMessage = 'Nothing matches that search.',
    String? sheetTitle,
  }) : super(
         initialValue: value,
         builder: (FormFieldState<T> state) {
           return _PickerFieldBody<T>(
             state: state,
             options: options,
             decoration: decoration,
             onChanged: onChanged,
             // Read back off the field rather than captured, because
             // `enabled` is a super parameter and is not in scope here.
             enabled: state.widget.enabled,
             searchHint: searchHint,
             emptyMessage: emptyMessage,
             sheetTitle: sheetTitle ?? decoration.labelText ?? 'Select',
           );
         },
       );

  @override
  FormFieldState<T> createState() => _SearchablePickerFieldState<T>();
}

/// Keeps the field in step when the caller rebuilds with a different value.
///
/// `FormField` only reads `initialValue` once, so without this a value changed
/// by the surrounding form - the destination being cleared because the source
/// changed, say - would stay on screen after it had already been dropped.
class _SearchablePickerFieldState<T> extends FormFieldState<T> {
  @override
  SearchablePickerField<T> get widget =>
      super.widget as SearchablePickerField<T>;

  @override
  void didUpdateWidget(SearchablePickerField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.initialValue != oldWidget.initialValue &&
        widget.initialValue != value) {
      setValue(widget.initialValue);
    }
  }
}

class _PickerFieldBody<T> extends StatelessWidget {
  const _PickerFieldBody({
    required this.state,
    required this.options,
    required this.decoration,
    required this.onChanged,
    required this.enabled,
    required this.searchHint,
    required this.emptyMessage,
    required this.sheetTitle,
  });

  final FormFieldState<T> state;
  final List<PickerOption<T>> options;
  final InputDecoration decoration;
  final ValueChanged<T?> onChanged;
  final bool enabled;
  final String searchHint;
  final String emptyMessage;
  final String sheetTitle;

  PickerOption<T>? get _selected {
    for (final option in options) {
      if (option.value == state.value) return option;
    }
    return null;
  }

  Future<void> _open(BuildContext context) async {
    if (!enabled) return;

    // Whatever has focus loses it first, or the keyboard stays up over the
    // sheet on a phone.
    FocusScope.of(context).unfocus();

    final wide = MediaQuery.sizeOf(context).width >= 720;

    final picked = wide
        ? await showDialog<_Picked<T>>(
            context: context,
            builder: (context) => Dialog(
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
                child: _PickerList<T>(
                  title: sheetTitle,
                  options: options,
                  selected: state.value,
                  searchHint: searchHint,
                  emptyMessage: emptyMessage,
                ),
              ),
            ),
          )
        : await showModalBottomSheet<_Picked<T>>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            showDragHandle: true,
            builder: (context) => FractionallySizedBox(
              heightFactor: 0.85,
              child: _PickerList<T>(
                title: sheetTitle,
                options: options,
                selected: state.value,
                searchHint: searchHint,
                emptyMessage: emptyMessage,
              ),
            ),
          );

    if (picked == null) return;

    state.didChange(picked.value);
    onChanged(picked.value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selected = _selected;

    return InkWell(
      onTap: enabled ? () => _open(context) : null,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: InputDecorator(
        decoration: decoration.copyWith(
          errorText: state.errorText,
          enabled: enabled,
          // The arrow says "this opens something", which is the one cue a
          // tappable InputDecorator otherwise loses against a text field.
          suffixIcon: decoration.suffixIcon ??
              Icon(
                Icons.arrow_drop_down_rounded,
                color: enabled
                    ? colors.onSurfaceVariant
                    : colors.onSurfaceVariant.withValues(alpha: 0.5),
              ),
        ),
        isEmpty: selected == null,
        child: selected == null
            ? null
            : Row(
                children: [
                  if (selected.icon != null) ...[
                    Icon(selected.icon, size: 20),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      selected.subtitle == null || selected.subtitle!.isEmpty
                          ? selected.label
                          : '${selected.label} — ${selected.subtitle}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: enabled
                            ? colors.onSurface
                            : colors.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// What the sheet hands back. A wrapper, so "chose the option whose value is
/// null" can be told apart from "dismissed the sheet".
@immutable
class _Picked<T> {
  const _Picked(this.value);

  final T value;
}

class _PickerList<T> extends StatefulWidget {
  const _PickerList({
    required this.title,
    required this.options,
    required this.selected,
    required this.searchHint,
    required this.emptyMessage,
  });

  final String title;
  final List<PickerOption<T>> options;
  final T? selected;
  final String searchHint;
  final String emptyMessage;

  @override
  State<_PickerList<T>> createState() => _PickerListState<T>();
}

class _PickerListState<T> extends State<_PickerList<T>> {
  final TextEditingController _search = TextEditingController();

  /// Above this many options the search field takes focus straight away:
  /// a long list is one somebody came here to search rather than to read.
  static const int _autofocusAbove = 10;

  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<PickerOption<T>> get _visible {
    final query = _query.trim().toLowerCase();

    if (query.isEmpty) return widget.options;

    // Every word has to appear somewhere, so "town lahore" finds
    // "Model Town Bazaar — Lahore" whichever order it is typed in.
    final words = query.split(RegExp(r'\s+'));

    return widget.options.where((option) {
      final haystack = option.haystack;
      return words.every(haystack.contains);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final visible = _visible;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: TextField(
            controller: _search,
            autofocus: widget.options.length > _autofocusAbove,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: widget.searchHint,
              prefixIcon: const Icon(Icons.search_rounded),
              isDense: true,
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        Divider(height: 1, color: colors.outlineVariant),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          size: 36,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          widget.emptyMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.xs,
                  ),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final option = visible[index];
                    final isSelected = option.value == widget.selected;

                    return ListTile(
                      leading: option.icon == null
                          ? null
                          : Icon(option.icon, size: 22),
                      title: Text(
                        option.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                      ),
                      subtitle:
                          option.subtitle == null || option.subtitle!.isEmpty
                          ? null
                          : Text(
                              option.subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      trailing: isSelected
                          ? Icon(
                              Icons.check_circle_rounded,
                              color: colors.primary,
                            )
                          : null,
                      selected: isSelected,
                      onTap: () =>
                          Navigator.of(context).pop(_Picked<T>(option.value)),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
