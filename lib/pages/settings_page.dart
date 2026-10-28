import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tmlink/core/app_controller.dart';
import 'package:tmlink/core/app_settings.dart';
import 'package:tmlink/core/tm_instance_detector.dart';
import 'package:tmlink/ui/components.dart';

class SettingsPage extends StatefulWidget {
  final AppController controller;
  const SettingsPage({super.key, required this.controller});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _form = GlobalKey<FormState>();
  final _tmHost = TextEditingController();
  final _tmKey = TextEditingController();
  final _obsUrl = TextEditingController();
  final _obsPassword = TextEditingController();
  final _detector = TmInstanceDetector();
  bool _dirty = false;
  bool _scanning = false;
  String? _scanMessage;
  List<DetectedTmInstance> _detected = [];
  AppController get app => widget.controller;

  @override
  void initState() {
    super.initState();
    _sync();
    app.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (!mounted) return;
    if (!_dirty && !app.savingSettings) _sync();
    setState(() {});
  }

  void _sync() {
    final s = app.settings;
    for (final entry in {
      _tmHost: s.tmHost,
      _tmKey: s.tmApiKey,
      _obsUrl: s.obsUrl,
      _obsPassword: s.obsPassword,
    }.entries) {
      if (entry.key.text != entry.value) entry.key.text = entry.value;
    }
  }

  void _edited(String _) => setState(() => _dirty = true);

  Future<void> _save({bool connect = false}) async {
    if (!_form.currentState!.validate()) return;
    final ok = await app.saveSettings(
      AppSettings(
        tmHost: app.developerMode ? app.settings.tmHost : _tmHost.text.trim(),
        tmApiKey: app.developerMode
            ? app.settings.tmApiKey
            : _tmKey.text.trim(),
        obsUrl: _obsUrl.text.trim(),
        obsPassword: _obsPassword.text,
        advancedUserMode: app.settings.advancedUserMode,
        matchMusicAutomation: app.settings.matchMusicAutomation,
      ),
    );
    if (!mounted || !ok) return;
    setState(() {
      _dirty = false;
      _sync();
    });
    if (connect) {
      await app.connectAll();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connection settings saved.')),
      );
    }
  }

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _scanMessage = 'Looking for Tournament Manager on your local network…';
    });
    try {
      final results = await _detector.scanLocalNetwork();
      if (!mounted) return;
      setState(() {
        _detected = results;
        _scanMessage = results.isEmpty
            ? 'No server found. You can enter its host manually.'
            : 'Found ${results.length} server${results.length == 1 ? '' : 's'}. Choose one below.';
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _scanMessage =
              'Discovery could not complete. Enter the TM host manually.',
        );
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled =
        !app.locked &&
        !app.connecting &&
        !app.loadingFields &&
        !app.testingScene;
    final checkEnabled = enabled && !_dirty && app.storageAvailable;
    final tmEnabled = enabled && !app.developerMode;
    final modeCard = Panel(
      child: Column(
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Advanced user mode'),
            subtitle: const Text(
              'Show technical match-data and OBS source settings.',
            ),
            value: app.settings.advancedUserMode,
            onChanged: enabled
                ? (value) async {
                    await app.setAdvancedUserMode(value);
                  }
                : null,
          ),
          if (Platform.isMacOS && app.settings.advancedUserMode) ...[
            const Divider(height: 20),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Pause music during matches'),
              subtitle: const Text(
                'Pause Spotify, Apple Music, or TIDAL when a match starts; resume when it ends. macOS may ask for Automation permission. TIDAL may also require Accessibility access.',
              ),
              value: app.settings.matchMusicAutomation,
              onChanged: enabled
                  ? (value) async {
                      await app.setMatchMusicAutomation(value);
                    }
                  : null,
            ),
            if (app.settings.matchMusicAutomation)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: enabled
                      ? () async => app.testMatchMusicAutomation()
                      : null,
                  icon: const Icon(CupertinoIcons.music_note),
                  label: const Text('Test pause and resume'),
                ),
              ),
          ],
        ],
      ),
    );
    final tmCard = Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(
            app.developerMode ? 'TM simulator' : 'Tournament Manager',
            CupertinoIcons.desktopcomputer,
            app.tmState,
          ),
          const SizedBox(height: 10),
          Text(
            app.developerMode
                ? 'TM is bypassed for this session. Use Scene Routing to activate test fields.'
                : 'Read field activations from your tournament server.',
          ),
          const SizedBox(height: 22),
          TextFormField(
            controller: _tmHost,
            enabled: tmEnabled,
            onChanged: _edited,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Server address',
              hintText: '192.168.1.10:8080',
            ),
            validator: (value) {
              if (app.developerMode) return null;
              try {
                normalizeTmUrl(value ?? '');
                return null;
              } catch (error) {
                return '$error';
              }
            },
          ),
          const SizedBox(height: 16),
          SecretField(
            controller: _tmKey,
            label: 'TM API key',
            enabled: tmEnabled,
            onChanged: _edited,
            helper: 'Use the key configured for this tournament server.',
          ),
          const SizedBox(height: 20),
          SelectableText(
            app.tmMessage,
            style: TextStyle(
              fontSize: 12,
              color: app.tmState == ServiceState.failed
                  ? Theme.of(context).colorScheme.error
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: checkEnabled && !app.developerMode
                    ? app.connectTm
                    : null,
                icon: const Icon(CupertinoIcons.link, size: 16),
                label: Text(app.developerMode ? 'TM bypassed' : 'Connect TM'),
              ),
              OutlinedButton.icon(
                onPressed: tmEnabled && !_scanning ? _scan : null,
                icon: const Icon(
                  CupertinoIcons.antenna_radiowaves_left_right,
                  size: 16,
                ),
                label: const Text('Find server'),
              ),
            ],
          ),
          if (_scanning) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          if (_scanMessage != null) ...[
            const SizedBox(height: 12),
            Text(_scanMessage!, style: Theme.of(context).textTheme.bodySmall),
          ],
          if (_detected.isNotEmpty) ...[
            const SizedBox(height: 12),
            ..._detected.map(
              (server) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(server.hostForInput),
                trailing: const Icon(CupertinoIcons.chevron_right, size: 14),
                onTap: tmEnabled
                    ? () {
                        _tmHost.text = server.hostForInput;
                        _edited('');
                      }
                    : null,
              ),
            ),
          ],
        ],
      ),
    );
    final obsCard = Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header('OBS Studio', CupertinoIcons.videocam, app.obsState),
          const SizedBox(height: 10),
          const Text('Control the program scene in your broadcast.'),
          const SizedBox(height: 22),
          TextFormField(
            controller: _obsUrl,
            enabled: enabled,
            autocorrect: false,
            onChanged: _edited,
            decoration: const InputDecoration(
              labelText: 'WebSocket address',
              hintText: 'ws://localhost:4455/',
            ),
            validator: (value) {
              try {
                normalizeObsUrl(value ?? '');
                return null;
              } catch (error) {
                return '$error';
              }
            },
          ),
          const SizedBox(height: 16),
          SecretField(
            controller: _obsPassword,
            label: 'WebSocket password',
            onChanged: _edited,
            enabled: enabled,
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'In OBS Studio',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                ),
                SizedBox(height: 6),
                Text(
                  'Open Tools → WebSocket Server Settings. Enable the server, then copy its port and password here.',
                  style: TextStyle(fontSize: 12, height: 1.6),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SelectableText(
            app.obsMessage,
            style: TextStyle(
              fontSize: 12,
              color: app.obsState == ServiceState.failed
                  ? Theme.of(context).colorScheme.error
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: checkEnabled ? app.connectObs : null,
            icon: const Icon(CupertinoIcons.link, size: 16),
            label: const Text('Connect OBS'),
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                CupertinoIcons.lock_shield,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'The TM API key and OBS password are stored in your system keychain.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PageHeading(
              title: 'Connections',
              subtitle:
                  'Set up your services once. Check access before you go live.',
            ),
            const SizedBox(height: 24),
            if (app.notice != null) ...[
              NoticeBanner(message: app.notice!, onDismiss: app.clearNotice),
              const SizedBox(height: 20),
            ],
            if (!app.storageAvailable) ...[
              NoticeBanner(
                message:
                    'Saved settings are unavailable. Retry after unlocking your keychain.',
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: app.initialize,
                child: const Text('Retry saved settings'),
              ),
              const SizedBox(height: 20),
            ],
            if (app.locked) ...[
              const NoticeBanner(
                message: 'Stop monitoring before changing connection settings.',
              ),
              const SizedBox(height: 20),
            ],
            modeCard,
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) => constraints.maxWidth >= 800
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: tmCard),
                        const SizedBox(width: 20),
                        Expanded(child: obsCard),
                      ],
                    )
                  : Column(
                      children: [tmCard, const SizedBox(height: 20), obsCard],
                    ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: enabled ? () => _save(connect: true) : null,
                  icon: app.savingSettings
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(CupertinoIcons.checkmark, size: 16),
                  label: const Text('Save & Connect'),
                ),
                OutlinedButton(
                  onPressed: enabled && _dirty ? () => _save() : null,
                  child: const Text('Save settings'),
                ),
                if (_dirty)
                  Text(
                    'Unsaved changes',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else
                  Text(
                    'Connections are checked without switching scenes.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(String title, IconData icon, ServiceState state) => Wrap(
    spacing: 12,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Icon(icon, size: 24, color: Theme.of(context).colorScheme.primary),
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      StatusBadge(
        state: state,
        label: title == 'TM simulator' ? 'Simulated' : null,
      ),
    ],
  );
  @override
  void dispose() {
    app.removeListener(_onControllerChanged);
    _detector.dispose();
    for (final controller in [_tmHost, _tmKey, _obsUrl, _obsPassword]) {
      controller.dispose();
    }
    super.dispose();
  }
}
