/// The Local AI Assistant screen.
///
/// Talks only to the laptop's Local AI server. There is no cloud fallback and
/// no second provider: if the laptop cannot be reached, the screen says so
/// plainly rather than quietly answering from somewhere else.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../local_ai_provider.dart';
import '../widgets/local_ai_composer.dart';
import '../widgets/local_ai_message_bubble.dart';
import '../widgets/local_ai_status_banner.dart';

class LocalAiScreen extends StatefulWidget {
  const LocalAiScreen({super.key});

  @override
  State<LocalAiScreen> createState() => _LocalAiScreenState();
}

class _LocalAiScreenState extends State<LocalAiScreen>
    with WidgetsBindingObserver {
  final ScrollController _scroll = ScrollController();

  /// Kept so dispose() can detach without looking the provider up in a
  /// context that is being torn down.
  late final LocalAiProvider _provider;

  int _shownMessages = 0;

  @override
  void initState() {
    super.initState();
    _provider = context.read<LocalAiProvider>();
    _provider.addListener(_onProviderChanged);
    WidgetsBinding.instance.addObserver(this);

    // Configuration is read from disk and the server is greeted once, after
    // the first frame so the screen appears immediately rather than waiting on
    // a laptop that may be asleep. From then on the banner is kept current
    // for as long as the screen is on view.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _provider.loadConfig();
      if (!mounted) return;
      if (_provider.isConfigured) await _provider.testConnection();
      if (!mounted) return;
      _provider.startMonitoring();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _provider.removeListener(_onProviderChanged);
    _provider.stopMonitoring();
    _scroll.dispose();
    super.dispose();
  }

  /// Health checks only while someone can see the result: not with the app
  /// in the background, where they would only drain a phone's battery.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _provider.startMonitoring();
      case AppLifecycleState.paused ||
          AppLifecycleState.hidden ||
          AppLifecycleState.detached:
        _provider.stopMonitoring();
      case AppLifecycleState.inactive:
        break;
    }
  }

  /// Shows the provider's one-off notices (the laptop found at a new address,
  /// a question refused before sending) and follows the conversation down as
  /// it grows.
  void _onProviderChanged() {
    if (!mounted) return;

    final notice = _provider.takeNotice();
    if (notice != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(notice)));
    }

    final count = _provider.messages.length;
    if (count > _shownMessages) _scrollToEnd();
    _shownMessages = count;
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send(String text) async {
    await _provider.send(text);
    _scrollToEnd();
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear this conversation?'),
        content: const Text(
          'The messages are removed from this device and from the AI server. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) await _provider.clearConversation();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LocalAiProvider>();
    final messages = provider.messages;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Assistant'),
        centerTitle: true,
        actions: [
          if (provider.hasConversation)
            IconButton(
              tooltip: 'Clear conversation',
              onPressed: provider.isSending ? null : _confirmClear,
              icon: const Icon(Icons.delete_outline),
            ),
          IconButton(
            tooltip: 'Check the connection',
            onPressed: provider.status == LocalAiStatus.checking
                ? null
                : () => provider.testConnection(),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'AI server settings',
            onPressed: () => context.push('/ai-assistant/settings'),
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const LocalAiStatusBanner(),
            Expanded(
              child: messages.isEmpty
                  ? const _EmptyState()
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      itemCount: messages.length,
                      itemBuilder: (context, index) =>
                          LocalAiMessageBubble(message: messages[index]),
                    ),
            ),
            LocalAiComposer(
              enabled: provider.isConfigured,
              sending: provider.isSending,
              canStop: provider.canStop,
              stopping: provider.isStopping,
              documentsMode: provider.documentsMode,
              documentsAvailable: provider.documentsAllowed,
              onChangedDocumentsMode: provider.setDocumentsMode,
              validate: provider.validateQuestion,
              onSend: _send,
              onStop: () => provider.stop(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown before the first question. Deliberately says what the assistant is,
/// where it runs and what it is given, because "private, on your own laptop,
/// with only what you may see" is the whole point of this feature and is not
/// obvious from an empty box.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.memory, size: 56, color: colors.primary),
            const SizedBox(height: 16),
            Text(
              'Private AI Assistant',
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Ask anything in English, Urdu or Roman Urdu. Answers come from '
              'the model running on your own laptop - nothing is sent to any '
              'cloud AI service.',
              style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Questions include the inventory data your account may see; no '
              'password, token or account id is sent.',
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  } 
}
 