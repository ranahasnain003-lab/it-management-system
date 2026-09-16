import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';

// =============================================================================
// PAGE LAYOUT
// =============================================================================

/// Standard page body: title row with optional actions, then content.
class WebPage extends StatelessWidget {
  const WebPage({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    required this.children,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth >= 1100
            ? 32.0
            : constraints.maxWidth >= 600
            ? 24.0
            : 16.0;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(horizontal, 24, horizontal, 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    spacing: 16,
                    runSpacing: 14,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth >= 900
                              ? constraints.maxWidth * 0.6
                              : constraints.maxWidth,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: constraints.maxWidth >= 600 ? 26 : 22,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.6,
                                color: colors.onSurface,
                              ),
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                subtitle!,
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.45,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (actions.isNotEmpty)
                        Wrap(spacing: 10, runSpacing: 10, children: actions),
                    ],
                  ),
                  const SizedBox(height: 24),
                  ...children,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Toolbar row for search + filters that wraps on narrow widths.
class WebToolbar extends StatelessWidget {
  const WebToolbar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

class WebSearchField extends StatelessWidget {
  const WebSearchField({
    super.key,
    required this.onChanged,
    this.hint = 'Search',
    this.width = 320,
    this.controller,
  });

  final ValueChanged<String> onChanged;
  final String hint;
  final double width;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = MediaQuery.sizeOf(context).width - 72;

        return SizedBox(
          width: width.clamp(0, available < 200 ? 200 : available).toDouble(),
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        );
      },
    );
  }
}

/// Compact dropdown filter with a label.
class WebFilterDropdown<T> extends StatelessWidget {
  const WebFilterDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.width = 200,
  });

  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  final double width;

  @override
  Widget build(BuildContext context) {
    final hasValue = items.containsKey(value);

    // The selected option disappeared from the data (e.g. the last asset of
    // a category was deleted). Report the fallback to the page too, otherwise
    // the field would read "All" while the old filter keeps hiding rows.
    if (!hasValue && items.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onChanged(items.keys.first);
      });
    }

    return SizedBox(
      width: width,
      child: DropdownButtonFormField<T>(
        initialValue: hasValue ? value : items.keys.first,
        isExpanded: true,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        icon: const Icon(Icons.keyboard_arrow_down_rounded),
        decoration: InputDecoration(
          isDense: true,
          labelText: label,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        items: [
          for (final entry in items.entries)
            DropdownMenuItem<T>(
              value: entry.key,
              child: Text(entry.value, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

// =============================================================================
// CARDS
// =============================================================================

/// Key metric tile: tinted icon, label, large value and a caption.
class WebStatCard extends StatelessWidget {
  const WebStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.caption,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            // Thin accent bar identifies the metric at a glance.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 3, color: color.withValues(alpha: 0.85)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            value,
                            style: TextStyle(
                              fontSize: 26,
                              height: 1.15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.6,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                        if (caption != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            caption!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.tint(color, theme.brightness),
                          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                        ),
                        child: Icon(
                          icon,
                          size: 21,
                          color: AppColors.onTint(color, theme.brightness),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Positioned(
                right: 6,
                bottom: 4,
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 14,
                  color: colors.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Responsive grid of fixed-height cards.
class WebCardGrid extends StatelessWidget {
  const WebCardGrid({
    super.key,
    required this.children,
    this.minItemWidth = 240,
    this.itemHeight = 112,
  });

  final List<Widget> children;
  final double minItemWidth;
  final double itemHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 16.0;
        final columns = ((constraints.maxWidth + spacing) / (minItemWidth + spacing))
            .floor()
            .clamp(1, 8);

        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
          childAspectRatio:
              (constraints.maxWidth - (columns - 1) * spacing) / columns / itemHeight,
          children: children,
        );
      },
    );
  }
}

/// Titled content card.
class WebSection extends StatelessWidget {
  const WebSection({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: colors.onSurface,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          Divider(height: 1, color: colors.outlineVariant),
          Padding(
            padding: const EdgeInsets.all(20),
            child: child,
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// STATES
// =============================================================================

class WebLoadingState extends StatelessWidget {
  const WebLoadingState({super.key, this.message = 'Loading...'});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(color: colors.onSurfaceVariant, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class WebMessageState extends StatelessWidget {
  const WebMessageState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.isError = false,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final bool isError;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tone = isError ? colors.error : colors.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.tint(tone, theme.brightness),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 30, color: tone),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 6),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.onSurfaceVariant, height: 1.5),
                ),
              ],
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// CHIPS
// =============================================================================

class WebStatusChip extends StatelessWidget {
  const WebStatusChip(this.status, {super.key});

  final String status;

  static Color colorFor(String status) => AppColors.forStatus(status);

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final color = colorFor(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.tint(color, brightness),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            status.isEmpty ? '—' : status,
            style: TextStyle(
              color: AppColors.onTint(color, brightness),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// FEEDBACK
// =============================================================================

String cleanError(Object error) {
  var text = error.toString().trim();

  if (text.startsWith('Exception: ')) {
    text = text.substring('Exception: '.length);
  }

  if (text.contains('permission-denied')) {
    return 'You do not have permission to perform this action.';
  }

  if (text.contains('unavailable') || text.contains('network')) {
    return 'Network error. Check your connection and try again.';
  }

  return text;
}

void showWebToast(BuildContext context, String message, {bool isError = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        width: 460,
        // Solid semantic tones keep white text readable in both themes.
        backgroundColor: isError ? AppColors.error : null,
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              color: isError ? Colors.white : const Color(0xFF4ADE80),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
        duration: Duration(seconds: isError ? 6 : 3),
      ),
    );
}

Future<bool> confirmWebAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final colors = Theme.of(dialogContext).colorScheme;

      return AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Text(message),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: colors.error,
                    foregroundColor: colors.onError,
                  )
                : null,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );

  return result == true;
}

/// Opens an existing full-screen form (mobile screen) inside a desktop dialog
/// so its validation and business logic are reused unchanged.
Future<T?> showWebFormDialog<T>(
  BuildContext context, {
  required Widget child,
  double maxWidth = 920,
}) {
  return showDialog<T>(
    context: context,
    builder: (dialogContext) {
      final size = MediaQuery.sizeOf(dialogContext);

      return Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: EdgeInsets.symmetric(
          horizontal: size.width < 700 ? 8 : 32,
          vertical: size.height < 600 ? 8 : 24,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxWidth,
            maxHeight: size.height * 0.92,
          ),
          // Explicit close control: the embedded screens are full screens on
          // Android, where the system back button closes them.
          child: Stack(
            children: [
              // Own messenger: a SnackBar raised by the embedded screen
              // (validation, duplicate ID, permission errors) would otherwise
              // be shown by the page behind the dialog and stay invisible.
              ScaffoldMessenger(child: child),
              Positioned(
                top: 6,
                right: 6,
                child: IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

String formatDateTime(DateTime? value) {
  if (value == null) return '—';

  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');

  return '${two(local.day)}/${two(local.month)}/${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}

String formatDate(DateTime? value) {
  if (value == null) return '—';

  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');

  return '${two(local.day)}/${two(local.month)}/${local.year}';
}

/// Runs a user-triggered export and reports a failure as an error toast
/// instead of an uncaught asynchronous error.
Future<void> runWebExport(
  BuildContext context,
  Future<Object?> Function() export,
) async {
  try {
    await export();
  } catch (e) {
    if (context.mounted) showWebToast(context, cleanError(e), isError: true);
  }
}

/// Dialog with one text field that owns (and disposes) its controller.
/// Returns the entered text, or null when cancelled.
Future<String?> showWebInputDialog(
  BuildContext context, {
  required String title,
  required String label,
  List<Widget> header = const [],
  String initialValue = '',
  int maxLines = 1,
  TextInputType? keyboardType,
  String? Function(String value)? validator,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _WebInputDialog(
      title: title,
      label: label,
      header: header,
      initialValue: initialValue,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      confirmLabel: confirmLabel,
      destructive: destructive,
    ),
  );
}

class _WebInputDialog extends StatefulWidget {
  const _WebInputDialog({
    required this.title,
    required this.label,
    required this.header,
    required this.initialValue,
    required this.maxLines,
    required this.keyboardType,
    required this.validator,
    required this.confirmLabel,
    required this.destructive,
  });

  final String title;
  final String label;
  final List<Widget> header;
  final String initialValue;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? Function(String value)? validator;
  final String confirmLabel;
  final bool destructive;

  @override
  State<_WebInputDialog> createState() => _WebInputDialogState();
}

class _WebInputDialogState extends State<_WebInputDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    final error = widget.validator?.call(value);

    if (error != null) {
      setState(() => _error = error);
      return;
    }

    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...widget.header,
              const SizedBox(height: 14),
              TextField(
                controller: _controller,
                autofocus: true,
                maxLines: widget.maxLines,
                keyboardType: widget.keyboardType,
                onSubmitted: widget.maxLines == 1 ? (_) => _submit() : null,
                decoration: InputDecoration(
                  labelText: widget.label,
                  errorText: _error,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: widget.destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                )
              : null,
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
