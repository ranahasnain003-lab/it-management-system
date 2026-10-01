/// One message in the Local AI conversation.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../local_ai_models.dart';

class LocalAiMessageBubble extends StatelessWidget {
  const LocalAiMessageBubble({super.key, required this.message});

  final LocalAiMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isUser = message.isUser;
    final failed = message.status == 'error';

    final background = isUser
        ? colors.primary
        : failed
        ? colors.errorContainer
        : colors.surfaceContainerHighest;

    final foreground = isUser
        ? colors.onPrimary
        : failed
        ? colors.onErrorContainer
        : colors.onSurface;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.content.isNotEmpty)
              SelectableText(
                message.content,
                style: text.bodyMedium?.copyWith(color: foreground, height: 1.4),
              ),

            // An answer that is still arriving, with nothing written yet. The
            // model can take a while to start on CPU, and the inventory data
            // is read before that, so silence here would read as a failure.
            if (message.isStreaming && message.content.isEmpty)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: foreground,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      message.progress ?? 'Thinking…',
                      style: text.bodySmall?.copyWith(color: foreground),
                    ),
                  ),
                ],
              ),

            if (message.wasStopped) ...[
              if (message.content.isNotEmpty) const SizedBox(height: 6),
              Text(
                'Stopped',
                style: text.labelSmall?.copyWith(
                  color: foreground.withValues(alpha: 0.75),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],

            if (failed && (message.error ?? '').isNotEmpty) ...[
              if (message.content.isNotEmpty) const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: 16, color: foreground),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message.error!,
                      style: text.bodySmall?.copyWith(color: foreground),
                    ),
                  ),
                ],
              ),
            ],

            if (!isUser &&
                message.appContext != null &&
                (message.answeredByApp || message.usedAppData)) ...[
              const SizedBox(height: 8),
              _AppDataBadge(
                usage: message.appContext!,
                byApp: message.answeredByApp,
                foreground: foreground,
              ),
            ],

            if (message.sources.isNotEmpty) ...[
              const SizedBox(height: 10),
              _Sources(sources: message.sources, foreground: foreground),
            ],

            if (message.documentsNote.trim().isNotEmpty &&
                message.sources.isEmpty) ...[
              const SizedBox(height: 8),
              Text(
                message.documentsNote,
                style: text.labelSmall?.copyWith(
                  color: foreground.withValues(alpha: 0.75),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Says the answer was grounded in this app's own records, and how fresh
/// they were. Without it an answer about stock levels reads the same as the
/// model's general knowledge, and the difference is the whole point.
///
/// [byApp] marks an answer the app worked out by itself, with no model: the
/// figures are the records' own, word for word.
class _AppDataBadge extends StatelessWidget {
  const _AppDataBadge({
    required this.usage,
    required this.byApp,
    required this.foreground,
  });

  final LocalAiAppContextUsage usage;
  final bool byApp;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final at = usage.retrievedAt;
    final what = byApp
        ? 'Straight from your IT Inventory records'
        : 'Based on your IT Inventory data';
    final label = at == null
        ? what
        : '$what · as of ${DateFormat('HH:mm').format(at.toLocal())}';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          byApp ? Icons.bolt_outlined : Icons.inventory_2_outlined,
          size: 13,
          color: foreground.withValues(alpha: 0.8),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground.withValues(alpha: 0.8),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// Citations for an answer drawn from the server's document library.
///
/// The passages come from the laptop's own indexed documents; the app never
/// searches or stores them.
class _Sources extends StatelessWidget {
  const _Sources({required this.sources, required this.foreground});

  final List<LocalAiSource> sources;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Based on your documents',
          style: text.labelSmall?.copyWith(
            color: foreground.withValues(alpha: 0.8),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        for (final source in sources)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Tooltip(
              message: source.snippet,
              child: Text(
                '[${source.n}] ${source.name}'
                '${source.location.isEmpty ? '' : ' - ${source.location}'}',
                style: text.labelSmall?.copyWith(
                  color: foreground.withValues(alpha: 0.85),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
