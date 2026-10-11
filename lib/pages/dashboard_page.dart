import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tmlink/core/app_controller.dart';
import 'package:tmlink/ui/components.dart';

class DashboardPage extends StatelessWidget {
  final AppController controller;
  final VoidCallback onConnections;
  const DashboardPage({
    super.key,
    required this.controller,
    required this.onConnections,
  });

  Future<void> _testScene(BuildContext context, String scene) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Test this scene?'),
        content: Text('OBS will switch its live program scene to “$scene”.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Switch scene'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.testScene(scene);
  }

  Future<void> _resetRouting(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset unreadable routing?'),
        content: const Text(
          'The original routing data will be backed up before clearing the assignments. You will need to assign scenes again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Back up & reset'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.resetUnreadableRouting();
  }

  @override
  Widget build(BuildContext context) {
    final app = controller;
    final theme = Theme.of(context);
    final issue = app.readinessIssue;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeading(
            title: 'Scene Routing',
            subtitle: 'The right camera. The right field. Automatically.',
            action: OutlinedButton.icon(
              onPressed:
                  !app.locked &&
                      !app.connecting &&
                      !app.loadingFields &&
                      !app.testingScene &&
                      app.storageAvailable
                  ? app.connectAll
                  : null,
              icon: const Icon(CupertinoIcons.arrow_clockwise, size: 15),
              label: const Text('Refresh services'),
            ),
          ),
          const SizedBox(height: 26),
          if (app.developerMode) ...[
            const NoticeBanner(
              message:
                  'Developer mode · TM is simulated. OBS scene switches are real.',
            ),
            const SizedBox(height: 20),
          ],
          if (app.notice != null) ...[
            NoticeBanner(message: app.notice!, onDismiss: app.clearNotice),
            const SizedBox(height: 20),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final tm = _serviceCard(
                context,
                app.developerMode ? 'TM simulator' : 'Tournament Manager',
                CupertinoIcons.desktopcomputer,
                app.tmState,
                app.tmMessage,
                app.developerMode
                    ? 'Local test fields · no TM connection'
                    : app.settings.tmHost,
              );
              final obs = _serviceCard(
                context,
                'OBS Studio',
                CupertinoIcons.videocam,
                app.obsState,
                app.obsMessage,
                app.settings.obsUrl,
              );
              return constraints.maxWidth >= 620
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: tm),
                        const SizedBox(width: 16),
                        Expanded(child: obs),
                      ],
                    )
                  : Column(children: [tm, const SizedBox(height: 16), obs]);
            },
          ),
          const SizedBox(height: 22),
          if (app.routingUnavailable) ...[
            const NoticeBanner(
              message:
                  'Saved routing is unreadable. Reset it with a backup to create new assignments.',
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => _resetRouting(context),
              child: const Text('Reset saved routing'),
            ),
            const SizedBox(height: 20),
          ],
          Panel(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final text = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StatusBadge(
                      state: app.monitoring
                          ? ServiceState.connected
                          : ServiceState.disconnected,
                      label: app.monitoring
                          ? app.developerMode
                                ? 'SIMULATION RUNNING'
                                : 'MONITORING LIVE'
                          : app.starting
                          ? 'STARTING'
                          : 'MONITORING PAUSED',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      app.monitoring
                          ? app.developerMode
                                ? 'Activate a test field below.'
                                : 'You’re connected to the action.'
                          : 'Ready when you are.',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 7),
                    Text(
                      app.monitoring
                          ? app.developerMode
                                ? 'Each activation switches the real OBS program scene using your test routing.'
                                : 'Field activations switch OBS using your saved scene routing.'
                          : issue ??
                                'All fields are mapped. Start monitoring to enable automatic scene switching.',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (app.currentScene != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Last confirmed scene: ${app.currentScene}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                );
                final actions = Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (app.monitoring || app.starting)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFD14343),
                        ),
                        onPressed: app.stopMonitoring,
                        icon: const Icon(CupertinoIcons.stop_fill, size: 14),
                        label: Text(
                          app.developerMode
                              ? 'Stop simulation'
                              : 'Stop monitoring',
                        ),
                      )
                    else
                      Tooltip(
                        message: issue ?? 'Begin automatic scene switching',
                        child: FilledButton.icon(
                          onPressed: app.canStart ? app.startMonitoring : null,
                          icon: const Icon(CupertinoIcons.play_fill, size: 14),
                          label: Text(
                            app.developerMode
                                ? 'Start simulation'
                                : 'Start monitoring',
                          ),
                        ),
                      ),
                    if ((!app.developerMode &&
                            app.tmState != ServiceState.connected) ||
                        app.obsState != ServiceState.connected)
                      TextButton(
                        onPressed: onConnections,
                        child: const Text('Set up connections'),
                      ),
                  ],
                );
                return constraints.maxWidth >= 650
                    ? Row(
                        children: [
                          Expanded(child: text),
                          const SizedBox(width: 24),
                          actions,
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [text, const SizedBox(height: 20), actions],
                      );
              },
            ),
          ),
          const SizedBox(height: 28),
          if (app.developerMode)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Simulate a field activation',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Map all test fields, then start simulation to enable these controls.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final field in app.fields)
                          OutlinedButton.icon(
                            onPressed: app.monitoring
                                ? () => app.simulateFieldActivation(field.id)
                                : null,
                            icon: const Icon(
                              CupertinoIcons.play_fill,
                              size: 14,
                            ),
                            label: Text('Activate ${field.name}'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Field → scene', style: theme.textTheme.titleMedium),
                    Text(
                      '${app.mappedCount} of ${app.fields.length} mapped',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (app.savingRouting)
                      const Text('Saving…', style: TextStyle(fontSize: 12)),
                    if (app.routingSaveFailed)
                      OutlinedButton(
                        onPressed: app.savingRouting ? null : app.saveRouting,
                        child: const Text('Retry saving'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose a scene for every field. Changes save automatically.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 22),
                if (app.fieldSets.isNotEmpty)
                  SizedBox(
                    width: 360,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(
                        'fieldset-${app.selectedFieldSetId}-${app.fieldSets.map((s) => s.id).join(',')}',
                      ),
                      initialValue: app.selectedFieldSetId,
                      isExpanded: true,
                      icon: const Icon(CupertinoIcons.chevron_down, size: 14),
                      decoration: const InputDecoration(labelText: 'Field set'),
                      items: app.fieldSets
                          .map(
                            (set) => DropdownMenuItem(
                              value: set.id,
                              child: Text(
                                set.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged:
                          app.locked || app.loadingFields || app.testingScene
                          ? null
                          : (id) {
                              if (id != null) app.selectFieldSet(id);
                            },
                    ),
                  ),
                const SizedBox(height: 20),
                if (app.loadingFields)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(36),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (app.fields.isEmpty)
                  EmptyState(
                    icon: CupertinoIcons.arrow_branch,
                    title: 'Let’s connect your broadcast',
                    message: app.tmState == ServiceState.connected
                        ? 'No fields are available. Refresh services or choose another field set.'
                        : 'Connect Tournament Manager and OBS, then assign a scene to each field.',
                    action: OutlinedButton(
                      onPressed: onConnections,
                      child: const Text('Open Connections'),
                    ),
                  )
                else
                  ...app.fields.map((field) {
                    final selected = app.sceneFor(field.id);
                    final missing =
                        selected != null && !app.scenes.contains(selected);
                    final values = ['', ...app.scenes, if (missing) selected];
                    final dropdown = DropdownButtonFormField<String>(
                      key: ValueKey(
                        '${app.selectedFieldSetId}-${field.id}-$selected-${app.scenes.join('|')}',
                      ),
                      initialValue: selected ?? '',
                      isExpanded: true,
                      icon: const Icon(CupertinoIcons.chevron_down, size: 14),
                      decoration: InputDecoration(
                        labelText: 'OBS scene',
                        errorText: missing
                            ? 'Scene unavailable. Choose a current scene.'
                            : null,
                      ),
                      items: values
                          .map(
                            (scene) => DropdownMenuItem(
                              value: scene,
                              child: Text(
                                scene.isEmpty
                                    ? 'Choose a scene…'
                                    : missing && scene == selected
                                    ? '$scene (unavailable)'
                                    : scene,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged:
                          app.locked ||
                              app.testingScene ||
                              app.obsState != ServiceState.connected
                          ? null
                          : (scene) => app.setMapping(
                              field.id,
                              scene == '' ? null : scene,
                            ),
                    );
                    final name = Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: .08,
                            ),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(
                            app.activeFieldId == field.id && app.monitoring
                                ? CupertinoIcons.play_fill
                                : CupertinoIcons.sportscourt,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                field.name,
                                style: theme.textTheme.titleMedium,
                              ),
                              Text(
                                'Field ${field.id}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                    final test = Tooltip(
                      message:
                          'Switch the live OBS program scene to test this mapping',
                      child: OutlinedButton(
                        onPressed:
                            !app.locked &&
                                !app.testingScene &&
                                selected != null &&
                                !missing &&
                                app.obsState == ServiceState.connected
                            ? () => _testScene(context, selected)
                            : null,
                        child: const Text('Test'),
                      ),
                    );
                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: theme.dividerColor.withValues(alpha: .35),
                          ),
                        ),
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) =>
                            constraints.maxWidth >= 580
                            ? Row(
                                children: [
                                  Expanded(flex: 3, child: name),
                                  const SizedBox(width: 18),
                                  Icon(
                                    CupertinoIcons.arrow_right,
                                    size: 15,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 18),
                                  Expanded(flex: 4, child: dropdown),
                                  const SizedBox(width: 12),
                                  test,
                                ],
                              )
                            : Column(
                                children: [
                                  name,
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(child: dropdown),
                                      const SizedBox(width: 12),
                                      test,
                                    ],
                                  ),
                                ],
                              ),
                      ),
                    );
                  }),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Icon(
                CupertinoIcons.checkmark_shield,
                size: 15,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Monitoring pauses if a connection fails or a mapped scene becomes unavailable.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _serviceCard(
    BuildContext context,
    String title,
    IconData icon,
    ServiceState state,
    String message,
    String address,
  ) => Panel(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            StatusBadge(
              state: state,
              label: title == 'TM simulator' ? 'Simulated' : null,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          address,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 5),
        Text(
          message,
          style: TextStyle(
            fontSize: 12,
            color: state == ServiceState.failed
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}
