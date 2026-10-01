/// Says how the Local AI server is doing, above the conversation.
///
/// It is deliberately loud when something is wrong. The alternative - failing
/// quietly and letting the screen look idle - is what makes a self-hosted
/// assistant feel broken rather than unreachable.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../local_ai_provider.dart';

class LocalAiStatusBanner extends StatelessWidget {
  const LocalAiStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LocalAiProvider>();
    final colors = Theme.of(context).colorScheme;

    final (icon, background, foreground, title, detail) = switch (provider.status) {
      LocalAiStatus.notConfigured => (
        Icons.settings_ethernet,
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
        'AI server not set up',
        // The same words as the navigation: Settings has an "AI Assistant
        // server" entry on both the phone and the web app, and the settings
        // button above leads to the same screen.
        'An administrator can set it up in Settings > AI Assistant server.',
      ),
      LocalAiStatus.checking => (
        Icons.sync,
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
        'Checking the AI server…',
        provider.config.baseUrl,
      ),
      LocalAiStatus.ready => (
        Icons.check_circle,
        colors.primaryContainer,
        colors.onPrimaryContainer,
        'Connected',
        _readyDetail(provider),
      ),
      LocalAiStatus.degraded => (
        Icons.warning_amber_rounded,
        colors.tertiaryContainer,
        colors.onTertiaryContainer,
        'AI server has a problem',
        provider.lastError?.userMessage ??
            provider.health?.problem ??
            'The server answered, but the model is not ready.',
      ),
      LocalAiStatus.unreachable => (
        Icons.cloud_off,
        colors.errorContainer,
        colors.onErrorContainer,
        'AI server unavailable',
        provider.lastError?.userMessage ??
            'The laptop could not be reached. Check that it is on and on the '
                'same network.',
      ),
      LocalAiStatus.unknown => (
        Icons.info_outline,
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
        'Not checked yet',
        provider.config.baseUrl,
      ),
    };

    // Nothing worth saying once it is working and the user is mid-conversation.
    if (provider.status == LocalAiStatus.ready && provider.hasConversation) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: foreground),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (detail.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: foreground),
                  ),
                ],
              ],
            ),
          ),
          if (provider.status == LocalAiStatus.checking)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
            ),
        ],
      ),
    );
  }

  /// Names the model, because "connected" on its own does not say whether the
  /// thing that answers questions is actually loaded.
  static String _readyDetail(LocalAiProvider provider) {
    final model = provider.model?.model ?? provider.health?.modelName ?? '';
    final queued = provider.health?.queueWaiting ?? 0;

    final parts = <String>[
      if (model.isNotEmpty) model,
      provider.config.baseUrl,
      if (queued > 0) '$queued question(s) queued',
    ];

    return parts.join(' · ');
  }
}
