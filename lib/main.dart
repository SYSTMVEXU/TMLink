import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tmlink/core/app_controller.dart';
import 'package:tmlink/core/config.dart';
import 'package:tmlink/pages/dashboard_page.dart';
import 'package:tmlink/pages/photos_page.dart';
import 'package:tmlink/pages/settings_page.dart';
import 'package:tmlink/ui/app_theme.dart';
import 'package:tmlink/ui/components.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TMLinkApp());
}

class TMLinkApp extends StatelessWidget {
  final AppController? controller;
  const TMLinkApp({super.key, this.controller});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Automated Tournament Stream',
    debugShowCheckedModeBanner: false,
    themeMode: ThemeMode.system,
    theme: appTheme(Brightness.light),
    darkTheme: appTheme(Brightness.dark),
    home: HomeScreen(controller: controller),
  );
}

class HomeScreen extends StatefulWidget {
  final AppController? controller;
  const HomeScreen({super.key, this.controller});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final AppController _app;
  Timer? _authorizationTimer;
  int _page = 0;
  @override
  void initState() {
    super.initState();
    _app = widget.controller ?? AppController();
    _app.initialize();
    // Refresh date-based notices even when the app remains open overnight.
    _authorizationTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _authorizationTimer?.cancel();
    if (widget.controller == null) _app.dispose();
    super.dispose();
  }

  Future<void> _downloadUpdate() async {
    try {
      if (await launchUrl(
        Uri.parse(Config.releasesUrl),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      // Browser launch failures should not interrupt OBS or TM monitoring.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: SelectableText('Download ATS at ${Config.releasesUrl}'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _app,
    builder: (context, _) {
      final narrow = MediaQuery.sizeOf(context).width < 850;
      final pages = [
        DashboardPage(
          controller: _app,
          onConnections: () => setState(() => _page = 1),
        ),
        SettingsPage(controller: _app),
        PhotosPage(controller: _app, selected: _page == 2),
        ActivityPage(controller: _app),
      ];
      return Scaffold(
        body: Row(
          children: [
            if (!narrow) _sidebar(context),
            Expanded(
              child: Column(
                children: [
                  if (_app.initialized && _app.authorizationNotice != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Panel(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _app.authorizationNotice!,
                              key: const ValueKey('authorization-notice'),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _downloadUpdate,
                              icon: const Icon(
                                CupertinoIcons.arrow_down_circle,
                              ),
                              label: const Text('Download update'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (narrow)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Row(
                        children: [
                          const Icon(
                            CupertinoIcons.link,
                            color: Color(0xFF007AFF),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'ATS',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          StatusBadge(
                            state: _app.monitoring
                                ? ServiceState.connected
                                : ServiceState.disconnected,
                            label: _app.monitoring
                                ? _app.developerMode
                                      ? 'Simulating'
                                      : 'Monitoring'
                                : 'Paused',
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: _app.initialized
                        ? IndexedStack(index: _page, children: pages)
                        : const Center(child: CircularProgressIndicator()),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: narrow
            ? NavigationBar(
                selectedIndex: _page,
                onDestinationSelected: (index) => setState(() => _page = index),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(CupertinoIcons.arrow_branch),
                    label: 'Scene Routing',
                  ),
                  NavigationDestination(
                    icon: Icon(CupertinoIcons.link),
                    label: 'Connections',
                  ),
                  NavigationDestination(
                    icon: Icon(CupertinoIcons.photo),
                    label: 'Photos',
                  ),
                  NavigationDestination(
                    icon: Icon(CupertinoIcons.clock),
                    label: 'Activity',
                  ),
                ],
              )
            : null,
      );
    },
  );

  Widget _sidebar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: .55),
        border: Border(
          right: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: .35),
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    CupertinoIcons.link,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ATS',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.5,
                        ),
                      ),
                      Text(
                        'Broadcast control',
                        style: TextStyle(fontSize: 9.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 38),
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 10),
            child: Text(
              'WORKSPACE',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          _nav(context, 0, CupertinoIcons.arrow_branch, 'Scene Routing'),
          _nav(context, 1, CupertinoIcons.link, 'Connections'),
          _nav(context, 2, CupertinoIcons.photo, 'Photos'),
          _nav(context, 3, CupertinoIcons.clock, 'Activity'),
          const Spacer(),
          Panel(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SERVICES',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: .8,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                _service(
                  _app.developerMode ? 'TM simulator' : 'Tournament Manager',
                  _app.tmState,
                ),
                const SizedBox(height: 10),
                _service('OBS Studio', _app.obsState),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              'Made by System Overload',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _nav(
    BuildContext context,
    int index,
    IconData icon,
    String title,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Material(
      color: _page == index
          ? Theme.of(context).colorScheme.primary.withValues(alpha: .10)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: Icon(
          icon,
          size: 19,
          color: _page == index ? Theme.of(context).colorScheme.primary : null,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: _page == index ? FontWeight.w600 : FontWeight.w400,
            color: _page == index
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
        ),
        onTap: () => setState(() => _page = index),
      ),
    ),
  );
  Widget _service(String title, ServiceState state) => Row(
    children: [
      Icon(
        CupertinoIcons.circle_fill,
        size: 7,
        color: switch (state) {
          ServiceState.connected => const Color(0xFF248A3D),
          ServiceState.failed => const Color(0xFFD14343),
          ServiceState.connecting => const Color(0xFF007AFF),
          ServiceState.disconnected => Colors.grey,
        },
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(title, style: const TextStyle(fontSize: 11))),
    ],
  );
}

class ActivityPage extends StatelessWidget {
  final AppController controller;
  const ActivityPage({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(32),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          title: 'Activity',
          subtitle:
              'Connection checks and confirmed scene changes. The latest 100 entries stay in this session.',
          action: OutlinedButton(
            onPressed: controller.activity.isEmpty
                ? null
                : controller.clearActivity,
            child: const Text('Clear activity'),
          ),
        ),
        const SizedBox(height: 28),
        Panel(
          child: controller.activity.isEmpty
              ? const EmptyState(
                  icon: CupertinoIcons.clock,
                  title: 'A clean slate',
                  message: 'Connect your services to start the activity log.',
                )
              : Column(
                  children: controller.activity.map((entry) {
                    final time =
                        '${entry.time.hour.toString().padLeft(2, '0')}:${entry.time.minute.toString().padLeft(2, '0')}:${entry.time.second.toString().padLeft(2, '0')}';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            entry.error
                                ? CupertinoIcons.exclamationmark_circle
                                : CupertinoIcons.checkmark_circle,
                            size: 18,
                            color: entry.error
                                ? const Color(0xFFD14343)
                                : const Color(0xFF248A3D),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: SelectableText(entry.message)),
                          const SizedBox(width: 12),
                          Text(
                            time,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    ),
  );
}
