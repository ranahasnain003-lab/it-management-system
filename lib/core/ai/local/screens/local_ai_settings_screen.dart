/// AI server configuration, for administrators.
///
/// Shows the connection status, the configured address, what the key may do,
/// the model, and a connection test. The API key is never displayed in full -
/// only the public `lai_<id>_` part, with the secret masked - so this screen
/// can be shown on a projector or in a screenshot without leaking anything.
///
/// Admins and Super Admins can change the address, key and certificate
/// fingerprint, find the laptop on the network, or reset to the build's
/// defaults. Everyone else sees the status read-only.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/user_provider.dart';
import '../../../services/permission_service.dart';
import '../local_ai_config.dart';
import '../local_ai_discovery.dart';
import '../local_ai_models.dart';
import '../local_ai_provider.dart';

class LocalAiSettingsScreen extends StatefulWidget {
  const LocalAiSettingsScreen({super.key});

  @override
  State<LocalAiSettingsScreen> createState() => _LocalAiSettingsScreenState();
}

class _LocalAiSettingsScreenState extends State<LocalAiSettingsScreen> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _url = TextEditingController();
  final TextEditingController _key = TextEditingController();
  final TextEditingController _fingerprint = TextEditingController();

  late final LocalAiProvider _provider;

  bool _saving = false;
  bool _loaded = false;
  bool _searching = false;
  bool _resetting = false;

  /// The server being saved from the search results, by identity.
  String? _using;

  /// Null until a search has run; empty when it found nothing.
  List<LocalAiDiscoveredServer>? _found;
  String? _searchError;

  /// What the fields were last filled with, to tell a saved change from one
  /// being typed.
  String _filledUrl = '';
  String _filledFingerprint = '';

  @override
  void initState() {
    super.initState();
    _provider = context.read<LocalAiProvider>();
    _provider.addListener(_onProviderChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _provider.loadConfig();
      if (!mounted) return;
      setState(() {
        _fillFromConfig();
        _loaded = true;
      });
      if (_provider.isConfigured && _provider.health == null) {
        await _provider.testConnection();
      }
    });
  }

  @override
  void dispose() {
    _provider.removeListener(_onProviderChanged);
    _url.dispose();
    _key.dispose();
    _fingerprint.dispose();
    super.dispose();
  }

  /// Keeps the fields on the saved values when they change underneath this
  /// screen - a connection test that found the laptop at a new address, say -
  /// unless the administrator is part-way through editing them.
  void _onProviderChanged() {
    if (!mounted) return;

    final config = _provider.config;
    final untouched =
        _url.text == _filledUrl && _fingerprint.text == _filledFingerprint;
    final moved =
        config.baseUrl != _filledUrl ||
        config.certificateFingerprint != _filledFingerprint;
    if (untouched && moved) setState(_fillFromConfig);

    final notice = _provider.takeNotice();
    if (notice != null) _snack(notice);
  }

  void _fillFromConfig() {
    _filledUrl = _provider.config.baseUrl;
    _filledFingerprint = _provider.config.certificateFingerprint;
    _url.text = _filledUrl;
    _fingerprint.text = _filledFingerprint;
    // The key field stays empty on purpose: it is write-only here. Leaving it
    // empty on save keeps whatever is already stored.
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    try {
      await _provider.saveConfig(
        baseUrl: _url.text,
        // Empty means "leave the stored key alone", so an administrator can
        // change the address without re-typing the secret.
        apiKey: _key.text.trim().isEmpty ? null : _key.text.trim(),
        certificateFingerprint: _fingerprint.text,
      );
      if (!mounted) return;
      _key.clear();
      setState(_fillFromConfig);
      _snack('AI server settings saved.');
    } on LocalAiException catch (error) {
      if (mounted) _snack(error.userMessage);
    } catch (error) {
      // Never includes the key.
      if (mounted) _snack('Could not save the settings securely.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _find() async {
    setState(() {
      _searching = true;
      _searchError = null;
      _found = null;
    });

    try {
      final servers = await _provider.findServers(
        apiKey: _key.text,
        address: _url.text,
      );
      if (!mounted) return;
      setState(() => _found = servers);
    } on LocalAiException catch (error) {
      if (mounted) setState(() => _searchError = error.userMessage);
    } catch (error) {
      if (mounted) {
        setState(() => _searchError = 'The search could not be run on this device.');
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _use(LocalAiDiscoveredServer server) async {
    setState(() => _using = server.identity);

    try {
      final url = await _provider.useDiscoveredServer(server, apiKey: _key.text);
      if (!mounted) return;
      _key.clear();
      setState(() {
        _fillFromConfig();
        _found = null;
      });
      _snack('Now using ${server.name.isEmpty ? 'the server' : server.name} at $url.');
    } on LocalAiException catch (error) {
      if (mounted) _snack(error.userMessage);
    } catch (error) {
      if (mounted) _snack('Could not save the settings securely.');
    } finally {
      if (mounted) setState(() => _using = null);
    }
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset the AI server settings?'),
        content: const Text(
          'The address, API key and certificate fingerprint saved on this '
          'device are removed, and the app goes back to the settings it was '
          'built with (often none). The conversation on this device is '
          'cleared.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _resetting = true);
    try {
      await _provider.resetConfig();
      if (!mounted) return;
      _key.clear();
      setState(() {
        _fillFromConfig();
        _found = null;
        _searchError = null;
      });
      _snack('AI server settings reset to the defaults.');
    } catch (error) {
      if (mounted) _snack('Could not reset the settings.');
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = context.watch<UserProvider>();
    final role = users.currentUserRole;

    // The address and key decide where this organisation's questions are sent,
    // so they follow the same bar as the app's other security settings rather
    // than inventing a new one.
    final mayConfigure =
        PermissionService.isSuperAdmin(role) || PermissionService.isAdmin(role);

    return Scaffold(
      appBar: AppBar(title: const Text('AI Assistant server'), centerTitle: true),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const _StatusCard(),
                const SizedBox(height: 14),
                const _PrivacyCard(),
                const SizedBox(height: 14),
                if (!mayConfigure)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.lock_outline),
                      title: Text('Read only'),
                      subtitle: Text(
                        'Only an Admin or Super Admin can change the AI server '
                        'settings.',
                      ),
                    ),
                  )
                else ...[
                  Form(
                    key: _form,
                    child: _Editor(
                      url: _url,
                      apiKey: _key,
                      fingerprint: _fingerprint,
                      saving: _saving,
                      searching: _searching,
                      discoverySupported: _provider.discoverySupported,
                      onSave: _save,
                      onFind: _find,
                    ),
                  ),
                  if (_searchError != null || _found != null) ...[
                    const SizedBox(height: 14),
                    _SearchResults(
                      error: _searchError,
                      servers: _found ?? const [],
                      pinned: _provider.config.certificateFingerprint,
                      using: _using,
                      onUse: _use,
                    ),
                  ],
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                      onPressed: _resetting || _saving ? null : _reset,
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('Reset to defaults'),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

/// Connection status, address, key permissions and model. Visible to anyone
/// who reaches the screen; it contains no secrets.
class _StatusCard extends StatelessWidget {
  const _StatusCard();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LocalAiProvider>();
    final config = provider.config;
    final health = provider.health;
    final model = provider.model;

    final (icon, colour, label) = switch (provider.status) {
      LocalAiStatus.ready => (Icons.check_circle, Colors.green, 'Connected'),
      LocalAiStatus.degraded => (
        Icons.warning_amber_rounded,
        Colors.orange,
        'Problem',
      ),
      LocalAiStatus.unreachable => (Icons.cloud_off, Colors.red, 'Unavailable'),
      LocalAiStatus.checking => (Icons.sync, Colors.blueGrey, 'Checking…'),
      LocalAiStatus.notConfigured => (
        Icons.settings_ethernet,
        Colors.blueGrey,
        'Not set up',
      ),
      LocalAiStatus.unknown => (Icons.info_outline, Colors.blueGrey, 'Unknown'),
    };

    final keyName = health?.clientName ?? '';

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: colour),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const Divider(height: 22),
            _Row('Server address', config.baseUrl.isEmpty ? 'not set' : config.baseUrl),
            _Row(
              'API key',
              keyName.isEmpty
                  ? config.redactedApiKey
                  : '${config.redactedApiKey} ("$keyName")',
            ),
            _Row('Key permissions', _permissions(health)),
            _Row('Configured by', switch (config.source) {
              LocalAiConfigSource.device => 'this device',
              LocalAiConfigSource.build => 'the app build',
              LocalAiConfigSource.none => 'nothing yet',
            }),
            if (config.isConfigured) _Row('Connection', _transport(config)),
            if (health != null) ...[
              _Row('Ollama', health.ollamaReachable
                  ? 'reachable${health.ollamaVersion.isEmpty ? '' : ' (${health.ollamaVersion})'}'
                  : 'not reachable'),
              _Row(
                'Model',
                health.modelName.isEmpty
                    ? 'unknown'
                    : '${health.modelName}${health.modelAvailable ? '' : ' - not installed'}',
              ),
              if (health.allowsDocuments)
                _Row('Documents indexed', '${health.indexedDocuments}'),
              _Row('Queue', '${health.queueRunning} running, ${health.queueWaiting} waiting'),
            ],
            if (model != null && model.contextWindow > 0)
              _Row('Context window', '${model.contextWindow} tokens'),
            if (provider.lastError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  provider.lastError!.userMessage,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: provider.status == LocalAiStatus.checking
                    ? null
                    : () => context.read<LocalAiProvider>().testConnection(),
                icon: const Icon(Icons.network_check),
                label: const Text('Test connection'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _permissions(LocalAiHealth? health) {
    if (health == null) return 'shown once connected';
    if (!health.hasClientInfo) return 'questions (this server does not report more)';
    return health.allowsDocuments
        ? 'questions and the document library'
        : 'questions only - the document library is not allowed for this key';
  }

  static String _transport(LocalAiConfig config) {
    if (config.isCleartext) {
      return 'Plain HTTP - use HTTPS when reaching the laptop over Wi-Fi';
    }
    if (config.isPinned) {
      return kIsWeb
          ? 'HTTPS - the browser checks the certificate (a web page cannot pin '
                'one)'
          : 'HTTPS, pinned to certificate ${config.shortFingerprint}';
    }
    return 'HTTPS, certificate checked against this device\'s trusted '
        'authorities';
  }
}

/// What leaves the app, and the network hints for this platform. Shown to
/// everyone: people asking questions deserve to know what goes with them.
class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
      height: 1.4,
    );

    Widget line(IconData icon, String message) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colors.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: muted)),
        ],
      ),
    );

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            line(
              Icons.shield_outlined,
              'Questions include the inventory data your account may see; no '
              'password, token or account id is sent. Answers are produced on '
              'the laptop - no cloud AI service is used.',
            ),
            if (kIsWeb) ...[
              line(
                Icons.travel_explore,
                'A web browser cannot search the network for the laptop, so '
                'the address is typed here, once per browser. If the laptop '
                'publishes a public address - a Tailscale Funnel name ending '
                '.ts.net - use that: it works from any phone or computer, on '
                'any network, and needs nothing installed. Otherwise use an '
                'address on this network: on a computer the laptop\'s NAME, '
                'for example https://DESKTOP-NAME.local:3001, because the name '
                'keeps working when its address changes; a phone\'s browser '
                'cannot look up .local names, so on this network a phone needs '
                'the number. "npm run lan -- -Action Status" on the laptop '
                'shows both.',
              ),
              line(
                Icons.https_outlined,
                'A browser decides for itself which certificates to trust and '
                'cannot pin one the way this app does on a phone. A public '
                '.ts.net address already has a certificate every browser '
                'trusts, so there is nothing to install. The addresses on this '
                'network use the laptop\'s own certificate authority, and that '
                '(ca.crt) has to be installed on each computer or phone that '
                'uses them - once, not per certificate.',
              ),
            ] else
              line(
                Icons.wifi_find,
                'On the same Wi-Fi or office network, the app finds the laptop '
                'by itself when its address changes. On another network, or '
                'with Wi-Fi client isolation, type the address instead.',
              ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _Editor extends StatelessWidget {
  const _Editor({
    required this.url,
    required this.apiKey,
    required this.fingerprint,
    required this.saving,
    required this.searching,
    required this.discoverySupported,
    required this.onSave,
    required this.onFind,
  });

  final TextEditingController url;
  final TextEditingController apiKey;
  final TextEditingController fingerprint;
  final bool saving;
  final bool searching;
  final bool discoverySupported;
  final VoidCallback onSave;
  final VoidCallback onFind;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Server',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (value) => LocalAiSettingsStore.addressProblem(value ?? ''),
              decoration: InputDecoration(
                labelText: 'Address',
                // On the web the public name is the one that works from any
                // network, so it is the example offered there.
                hintText: kIsWeb ? 'https://laptop-name.tailnet.ts.net' : 'https://192.168.1.50:3001',
                helperText: kIsWeb
                    ? 'The laptop running the AI server: its public .ts.net '
                          'name, or its address on this network.'
                    : 'The laptop running the AI server. From an Android '
                          'emulator on the laptop: http://10.0.2.2:3000',
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: apiKey,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'API key',
                hintText: 'leave empty to keep the current key',
                helperText:
                    'Created on the laptop with: npm run api-key -- create '
                    '--name "IT Management System"',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: fingerprint,
              autocorrect: false,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (value) =>
                  LocalAiSettingsStore.fingerprintProblem(value ?? ''),
              decoration: const InputDecoration(
                labelText: 'Certificate fingerprint (optional)',
                hintText: 'SHA-256, for the laptop\'s HTTPS certificate',
                helperText:
                    'Printed by create-certificate.ps1. When set, this device '
                    'accepts that certificate and no other.',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 10,
              runSpacing: 10,
              children: [
                if (discoverySupported)
                  OutlinedButton.icon(
                    onPressed: searching || saving ? null : onFind,
                    icon: searching
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_find),
                    label: const Text('Find server on this network'),
                  ),
                FilledButton.icon(
                  onPressed: saving || searching ? null : onSave,
                  icon: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Save and test'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Servers that answered the search with a valid proof. Only these are
/// listed: anything that answered without holding the key was already
/// discarded, unseen.
class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.error,
    required this.servers,
    required this.pinned,
    required this.using,
    required this.onUse,
  });

  final String? error;
  final List<LocalAiDiscoveredServer> servers;
  final String pinned;
  final String? using;
  final ValueChanged<LocalAiDiscoveredServer> onUse;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    Widget body;
    if (error != null) {
      body = Text(error!, style: text.bodyMedium?.copyWith(color: colors.error));
    } else if (servers.isEmpty) {
      body = Text(
        'No server answered. Check that the laptop is on and the server is '
        'running with LAN access, that this device is on the same network, '
        'and that the API key is the one created on the laptop. Otherwise '
        'type the address shown by "npm run lan -- -Action Status".',
        style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final server in servers)
            _ServerTile(
              server: server,
              pinned: pinned,
              busy: using == server.identity,
              enabled: using == null,
              onUse: () => onUse(server),
            ),
        ],
      );
    }

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Servers found',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            body,
          ],
        ),
      ),
    );
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.server,
    required this.pinned,
    required this.busy,
    required this.enabled,
    required this.onUse,
  });

  final LocalAiDiscoveredServer server;
  final String pinned;
  final bool busy;
  final bool enabled;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final fingerprint = server.certSha256 ?? '';
    final differentCertificate =
        pinned.isNotEmpty && fingerprint.isNotEmpty && fingerprint != pinned;
    // Choosing it saves no pin (there is no certificate to pin), so the
    // administrator should know the protection they have now goes away.
    final dropsPin = pinned.isNotEmpty && !server.isSecure;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                server.isSecure ? Icons.lock_outline : Icons.lock_open,
                size: 18,
                color: server.isSecure ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  server.name.isEmpty ? 'Local AI server' : server.name,
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _Row('Address', server.addresses.map((a) => '$a:${server.port}').join(', ')),
          _Row(
            'Connection',
            server.isSecure ? 'Secure (HTTPS)' : 'Not encrypted (HTTP)',
          ),
          _Row(
            'Fingerprint',
            fingerprint.isEmpty
                ? 'none'
                : LocalAiConfig.shortenFingerprint(fingerprint),
          ),
          if (differentCertificate)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'This is a different certificate from the one pinned on this '
                'device. Use it only if the certificate was re-created on the '
                'laptop.',
                style: text.bodySmall?.copyWith(color: colors.error),
              ),
            ),
          if (dropsPin)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'This server is not encrypted. Using it removes the '
                'certificate pinned on this device, and the API key and '
                'questions travel over the network unencrypted.',
                style: text.bodySmall?.copyWith(color: colors.error),
              ),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: enabled ? onUse : null,
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text('Use this server'),
            ),
          ),
        ],
      ),
    );
  }
}
