/// The message box: type a question, send it, or stop the answer.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../local_ai_models.dart';

class LocalAiComposer extends StatefulWidget {
  const LocalAiComposer({
    super.key,
    required this.enabled,
    required this.sending,
    required this.canStop,
    this.stopping = false,
    required this.documentsMode,
    this.documentsAvailable = false,
    required this.onChangedDocumentsMode,
    required this.onSend,
    required this.onStop,
    this.validate,
  });

  final bool enabled;
  final bool sending;
  final bool canStop;

  /// Stop was pressed and the answer has not ended yet.
  final bool stopping;

  final LocalAiDocumentsMode documentsMode;

  /// Whether the API key may use the laptop's document library at all. The
  /// selector is not shown otherwise: offering a choice the server refuses
  /// would only produce errors.
  final bool documentsAvailable;

  final ValueChanged<LocalAiDocumentsMode> onChangedDocumentsMode;
  final ValueChanged<String> onSend;
  final VoidCallback onStop;

  /// Says why a question cannot be sent (too long, signed out…), or null.
  /// Checked before the box is cleared, so a long question is not lost.
  final String? Function(String text)? validate;

  @override
  State<LocalAiComposer> createState() => _LocalAiComposerState();
}

class _LocalAiComposerState extends State<LocalAiComposer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.sending || !widget.enabled) return;

    final problem = widget.validate?.call(text);
    if (problem != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(problem)));
      return;
    }

    _controller.clear();
    widget.onSend(text);
    // Kept focused so a follow-up can be typed straight away, which is how
    // these conversations actually go.
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final showToolbar =
        widget.documentsAvailable || widget.canStop || widget.stopping;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showToolbar) ...[
            Row(
              children: [
                if (widget.documentsAvailable)
                  _DocumentsSelector(
                    mode: widget.documentsMode,
                    enabled: widget.enabled && !widget.sending,
                    onChanged: widget.onChangedDocumentsMode,
                  ),
                const Spacer(),
                if (widget.canStop)
                  TextButton.icon(
                    onPressed: widget.onStop,
                    icon: const Icon(Icons.stop_circle_outlined, size: 18),
                    label: const Text('Stop'),
                  )
                else if (widget.stopping)
                  const TextButton(onPressed: null, child: Text('Stopping…')),
              ],
            ),
            const SizedBox(height: 4),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Shortcuts(
                  shortcuts: const {
                    SingleActivator(LogicalKeyboardKey.enter): _SubmitIntent(),
                  },
                  child: Actions(
                    actions: {
                      _SubmitIntent: CallbackAction<_SubmitIntent>(
                        onInvoke: (_) {
                          _submit();
                          return null;
                        },
                      ),
                    },
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      enabled: widget.enabled,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      keyboardType: TextInputType.multiline,
                      decoration: InputDecoration(
                        hintText: widget.enabled
                            ? 'Ask anything - English, Urdu or Roman Urdu'
                            : 'The AI server is not set up yet',
                        filled: true,
                        fillColor: colors.surfaceContainerHighest,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: widget.enabled && !widget.sending ? _submit : null,
                icon: widget.sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                tooltip: 'Send',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SubmitIntent extends Intent {
  const _SubmitIntent();
}

/// Chooses whether the laptop's document library is searched for this question.
///
/// The retrieval itself is entirely the server's; this only picks the mode the
/// contract defines.
class _DocumentsSelector extends StatelessWidget {
  const _DocumentsSelector({
    required this.mode,
    required this.enabled,
    required this.onChanged,
  });

  final LocalAiDocumentsMode mode;
  final bool enabled;
  final ValueChanged<LocalAiDocumentsMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<LocalAiDocumentsMode>(
      enabled: enabled,
      initialValue: mode,
      onSelected: onChanged,
      tooltip: 'Whether to search the documents on the laptop',
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: LocalAiDocumentsMode.off,
          child: Text('Documents: off'),
        ),
        PopupMenuItem(
          value: LocalAiDocumentsMode.auto,
          child: Text('Documents: automatic'),
        ),
        PopupMenuItem(
          value: LocalAiDocumentsMode.only,
          child: Text('Documents only'),
        ),
      ],
      child: Chip(
        avatar: const Icon(Icons.description_outlined, size: 16),
        label: Text(switch (mode) {
          LocalAiDocumentsMode.auto => 'Docs: auto',
          LocalAiDocumentsMode.only => 'Docs only',
          LocalAiDocumentsMode.off => 'Docs: off',
        }),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
