import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tmlink/core/app_controller.dart';
import 'package:tmlink/ui/components.dart';

class UpcomingPanel extends StatefulWidget {
  final AppController controller;
  const UpcomingPanel({super.key, required this.controller});
  @override
  State<UpcomingPanel> createState() => _UpcomingPanelState();
}

class _UpcomingPanelState extends State<UpcomingPanel> {
  late final TextEditingController _division;
  AppController get app => widget.controller;
  @override
  void initState() {
    super.initState();
    _division = TextEditingController(text: app.upcoming.divisionId);
  }

  @override
  void dispose() {
    _division.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !app.locked && !app.connecting && !app.testingScene;
    final missing =
        app.obsState == ServiceState.connected &&
        !app.scenes.contains(app.upcoming.scene);
    final values = {...app.scenes, app.upcoming.scene}.toList()..sort();
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Upcoming match preview',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Queue a match → show the preview. Start the match → show its field camera.',
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey('${app.upcoming.scene}|${values.join('|')}'),
            initialValue: app.upcoming.scene,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Upcoming match scene',
              errorText: missing ? 'Choose an available OBS scene.' : null,
            ),
            items: values
                .map(
                  (scene) => DropdownMenuItem(
                    value: scene,
                    child: Text(scene, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: enabled && app.obsState == ServiceState.connected
                ? (value) {
                    if (value != null) {
                      app.saveUpcomingSettings(
                        app.upcoming.copyWith(scene: value),
                      );
                    }
                  }
                : null,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: enabled ? app.chooseTeamAssetsFolder : null,
                icon: const Icon(CupertinoIcons.folder, size: 16),
                label: Text(
                  app.importingAssets
                      ? 'Setting up…'
                      : app.upcoming.assetsDirectory.isEmpty
                      ? 'Set up image folder'
                      : 'Set up folder again',
                ),
              ),
              OutlinedButton.icon(
                onPressed: app.upcoming.assetsDirectory.isEmpty
                    ? null
                    : app.openTeamAssetsFolder,
                icon: const Icon(CupertinoIcons.folder_open, size: 16),
                label: const Text('Open asset folder'),
              ),
              OutlinedButton(
                onPressed: app.upcoming.assetsDirectory.isEmpty || !enabled
                    ? null
                    : app.refreshTeamRoster,
                child: const Text('Refresh roster'),
              ),
              Text(
                '${app.upcoming.teams.length} team records${app.upcoming.assetsDirectory.isEmpty ? '' : ' · folder connected'}',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'ATS refreshes teams.csv automatically when it connects to TM. You can also edit the file manually and refresh the roster. Add team-number.png and team-number.jpg files to the matching photo folders; default_robot.png and default_robot.jpg are used as fallbacks.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (app.queuedMatch != null) ...[
            const SizedBox(height: 16),
            Text(
              'Queued: ${app.queuedMatch!.label} · ${app.queuedMatch!.displayTeams.join(' / ')}',
            ),
          ],
          if (app.settings.advancedUserMode) ...[
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Match data and OBS source names'),
              children: [
                const SizedBox(height: 12),
                TextField(
                  controller: _division,
                  enabled: enabled,
                  decoration: const InputDecoration(
                    labelText: 'TM division ID',
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton(
                      onPressed: enabled
                          ? () => app.saveUpcomingSettings(
                              app.upcoming.copyWith(
                                divisionId: _division.text.trim(),
                              ),
                            )
                          : null,
                      child: const Text('Save division'),
                    ),
                    OutlinedButton(
                      onPressed:
                          !app.developerMode &&
                              !app.loadingMatches &&
                              app.tmState == ServiceState.connected
                          ? app.refreshMatches
                          : null,
                      child: Text(
                        app.loadingMatches
                            ? 'Refreshing…'
                            : 'Refresh match list',
                      ),
                    ),
                    OutlinedButton(
                      onPressed:
                          !app.developerMode &&
                              !app.loadingMatches &&
                              app.tmState == ServiceState.connected
                          ? app.startEliminations
                          : null,
                      child: Text(
                        app.eliminationsMode
                            ? 'Eliminations refresh active'
                            : 'Start eliminations',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    'Match label: MatchStr\nFor each team 1–4: Team1Number, Team1Name, Team1Org, Team1IMG, Team1Photo (replace 1 with 2, 3, or 4).\nMissing images use default_robot.png and default_robot.jpg in their respective folders.',
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
