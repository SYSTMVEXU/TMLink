import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:tmlink/core/app_controller.dart';
import 'package:tmlink/core/upcoming_match.dart';
import 'package:tmlink/ui/components.dart';

enum PhotoFilter { all, robot, team }

class _TeamPhotos {
  final String number;
  final TeamInfo info;
  final String? robot;
  final String? team;

  const _TeamPhotos({
    required this.number,
    required this.info,
    this.robot,
    this.team,
  });
}

class PhotosPage extends StatefulWidget {
  final AppController controller;
  final bool selected;

  const PhotosPage({
    super.key,
    required this.controller,
    required this.selected,
  });

  @override
  State<PhotosPage> createState() => _PhotosPageState();
}

class _PhotosPageState extends State<PhotosPage> {
  final _search = TextEditingController();
  List<_TeamPhotos> _teams = [];
  String _loadedDirectory = '';
  String? _defaultRobot;
  String? _defaultTeam;
  String? _error;
  bool _loading = false;
  PhotoFilter _filter = PhotoFilter.all;
  int _scanRevision = 0;

  AppController get app => widget.controller;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    if (widget.selected) _loadAssets();
  }

  @override
  void didUpdateWidget(covariant PhotosPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final directory = app.upcoming.assetsDirectory;
    if ((widget.selected && !oldWidget.selected) ||
        directory != _loadedDirectory) {
      _loadAssets();
    }
  }

  void _onSearchChanged() => setState(() {});

  @override
  void dispose() {
    _scanRevision++;
    _search
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadAssets() async {
    final revision = ++_scanRevision;
    final root = app.upcoming.assetsDirectory;
    if (root.isEmpty) {
      setState(() {
        _loadedDirectory = '';
        _teams = [];
        _defaultRobot = null;
        _defaultTeam = null;
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final robotFiles = await _imagesIn(p.join(root, 'robot_images'));
      final teamFiles = await _imagesIn(p.join(root, 'team_photos'));
      if (!mounted || revision != _scanRevision) return;

      String? defaultFile(Map<String, String> images) {
        for (final extension in ['.png', '.jpg', '.jpeg']) {
          final found = images['default_robot$extension'];
          if (found != null) return found;
        }
        return null;
      }

      final robotDefault = defaultFile(robotFiles);
      final teamDefault = defaultFile(teamFiles);
      final numbers = <String>{
        ...app.upcoming.teams.keys.map((number) => number.toUpperCase()),
        ...robotFiles.keys.map(_teamNumberForFile).whereType<String>(),
        ...teamFiles.keys.map(_teamNumberForFile).whereType<String>(),
      }..removeWhere((number) => number.isEmpty);
      final teams =
          numbers.map((number) {
            final info = app.upcoming.teams[number] ?? const TeamInfo();
            return _TeamPhotos(
              number: number,
              info: info,
              robot: _imageFor(robotFiles, number),
              team: _imageFor(teamFiles, number),
            );
          }).toList()..sort((a, b) {
            final numberOrder = a.number.compareTo(b.number);
            if (numberOrder != 0) return numberOrder;
            return a.info.name.toLowerCase().compareTo(
              b.info.name.toLowerCase(),
            );
          });

      setState(() {
        _loadedDirectory = root;
        _teams = teams;
        _defaultRobot = robotDefault;
        _defaultTeam = teamDefault;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || revision != _scanRevision) return;
      setState(() {
        _loadedDirectory = root;
        _teams = [];
        _loading = false;
        _error = 'Could not read the ATS photo folders. Check folder access.';
      });
    }
  }

  Future<Map<String, String>> _imagesIn(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) return {};
    final files = <String, String>{};
    final entries = await directory.list(followLinks: false).toList();
    entries.sort(
      (a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()),
    );
    for (final entry in entries) {
      if (entry is! File) continue;
      final extension = p.extension(entry.path).toLowerCase();
      if (!const {'.png', '.jpg', '.jpeg'}.contains(extension)) continue;
      final filename = p.basename(entry.path).toLowerCase();
      files.putIfAbsent(filename, () => entry.path);
    }
    return files;
  }

  String? _teamNumberForFile(String filename) {
    final number = p.basenameWithoutExtension(filename);
    if (number.toLowerCase() == 'default_robot') return null;
    return RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(number)
        ? number.toUpperCase()
        : null;
  }

  String? _imageFor(Map<String, String> files, String number) {
    for (final extension in ['.png', '.jpg', '.jpeg']) {
      final found = files['${number.toLowerCase()}$extension'];
      if (found != null) return found;
    }
    return null;
  }

  Future<void> _setupFolder() async {
    await app.chooseTeamAssetsFolder();
    if (mounted) await _loadAssets();
  }

  Future<void> _refresh() async {
    await app.refreshTeamRoster();
    if (mounted) await _loadAssets();
  }

  List<_TeamPhotos> get _visibleTeams {
    final query = _search.text.trim().toLowerCase();
    return _teams.where((team) {
      final hasImage = switch (_filter) {
        PhotoFilter.all => true,
        PhotoFilter.robot => team.robot != null,
        PhotoFilter.team => team.team != null,
      };
      if (!hasImage) return false;
      if (query.isEmpty) return true;
      return team.number.toLowerCase().contains(query) ||
          team.info.name.toLowerCase().contains(query) ||
          team.info.organization.toLowerCase().contains(query);
    }).toList();
  }

  int _countImages(bool robot) => _teams.where((team) {
    if (robot) return team.robot != null;
    return team.team != null;
  }).length;

  void _showPreview(String title, String? image, String? fallback) {
    final path = image ?? fallback;
    if (path == null) return;
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 760),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close preview',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(CupertinoIcons.xmark),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: Center(
                    child: Image.file(
                      File(path),
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const EmptyState(
                        icon: CupertinoIcons.exclamationmark_triangle,
                        title: 'Image could not be opened',
                        message: 'Check that the file is a supported image.',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SelectableText(p.basename(path)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final root = app.upcoming.assetsDirectory;
    final visible = _visibleTeams;
    final directoryReady = root.isNotEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeading(
            title: 'Photos',
            subtitle:
                'Browse the robot and team images ATS uses for match previews.',
            action: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: directoryReady
                      ? app.openTeamAssetsFolder
                      : _setupFolder,
                  icon: const Icon(CupertinoIcons.folder_open, size: 16),
                  label: Text(
                    directoryReady
                        ? 'Open asset folder'
                        : 'Set up image folder',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: directoryReady && !_loading ? _refresh : null,
                  icon: const Icon(CupertinoIcons.arrow_clockwise, size: 16),
                  label: const Text('Refresh'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          if (app.notice != null) ...[
            NoticeBanner(message: app.notice!, onDismiss: app.clearNotice),
            const SizedBox(height: 16),
          ],
          if (!directoryReady)
            Panel(
              child: EmptyState(
                icon: CupertinoIcons.photo,
                title: 'Set up your photo folder',
                message:
                    'ATS will create Documents/ATS with a roster and folders for robot and team photos.',
                action: FilledButton.icon(
                  onPressed: _setupFolder,
                  icon: const Icon(CupertinoIcons.folder, size: 16),
                  label: const Text('Set up image folder'),
                ),
              ),
            )
          else ...[
            Panel(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(CupertinoIcons.folder, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          root,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      labelText: 'Search teams',
                      hintText: 'Team number, name, or organization',
                      prefixIcon: const Icon(CupertinoIcons.search),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: _search.clear,
                              icon: const Icon(
                                CupertinoIcons.xmark_circle_fill,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SegmentedButton<PhotoFilter>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: PhotoFilter.all,
                          label: Text('All'),
                        ),
                        ButtonSegment(
                          value: PhotoFilter.robot,
                          label: Text('Robot photos'),
                        ),
                        ButtonSegment(
                          value: PhotoFilter.team,
                          label: Text('Team photos'),
                        ),
                      ],
                      selected: {_filter},
                      onSelectionChanged: (selection) =>
                          setState(() => _filter = selection.first),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_teams.length} teams · ${_countImages(true)} robot photos · ${_countImages(false)} team photos${_search.text.isEmpty ? '' : ' · ${visible.length} shown'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (_loading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              NoticeBanner(message: _error!),
            ],
            const SizedBox(height: 14),
            if (!_loading && visible.isEmpty)
              Panel(
                child: EmptyState(
                  icon: CupertinoIcons.photo,
                  title: _search.text.isNotEmpty
                      ? 'No matches'
                      : switch (_filter) {
                          PhotoFilter.all => 'No teams found',
                          PhotoFilter.robot => 'No robot photos found',
                          PhotoFilter.team => 'No team photos found',
                        },
                  message: _search.text.isNotEmpty
                      ? 'Try another search or photo filter.'
                      : _filter == PhotoFilter.all
                      ? 'Add teams to teams.csv or place their images in robot_images and team_photos.'
                      : 'Add images to the matching photo folder, or try another filter.',
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = (constraints.maxWidth / 330).floor().clamp(
                    1,
                    4,
                  );
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      mainAxisExtent: _filter == PhotoFilter.all ? 316 : 274,
                    ),
                    itemCount: visible.length,
                    itemBuilder: (context, index) => _teamCard(visible[index]),
                  );
                },
              ),
          ],
        ],
      ),
    );
  }

  Widget _teamCard(_TeamPhotos team) {
    final hasBoth = _filter == PhotoFilter.all;
    final name = team.info.name.trim().isEmpty
        ? 'Team ${team.number}'
        : team.info.name;
    return Panel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(team.number, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(
            team.info.organization.trim().isEmpty
                ? name
                : '$name · ${team.info.organization}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              children: [
                if (_filter != PhotoFilter.team)
                  Expanded(
                    child: _photoTile(
                      label: 'Robot',
                      path: team.robot,
                      fallback: _defaultRobot,
                      onTap: () => _showPreview(
                        '$name · Robot',
                        team.robot,
                        _defaultRobot,
                      ),
                    ),
                  ),
                if (hasBoth) const SizedBox(width: 10),
                if (_filter != PhotoFilter.robot)
                  Expanded(
                    child: _photoTile(
                      label: 'Team photo',
                      path: team.team,
                      fallback: _defaultTeam,
                      onTap: () => _showPreview(
                        '$name · Team photo',
                        team.team,
                        _defaultTeam,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoTile({
    required String label,
    required String? path,
    required String? fallback,
    required VoidCallback onTap,
  }) {
    final actual = path != null;
    final shown = path ?? fallback;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 6),
        Expanded(
          child: Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: shown == null ? null : onTap,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (shown == null)
                    const EmptyState(
                      icon: CupertinoIcons.photo,
                      title: 'Missing',
                      message: 'No image or default',
                    )
                  else
                    Image.file(
                      File(shown),
                      fit: BoxFit.cover,
                      cacheWidth: 520,
                      errorBuilder: (_, _, _) => const Center(
                        child: Icon(CupertinoIcons.exclamationmark_triangle),
                      ),
                    ),
                  if (!actual && shown != null)
                    Align(
                      alignment: Alignment.topLeft,
                      child: Container(
                        margin: const EdgeInsets.all(7),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .72),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Default image',
                          style: TextStyle(color: Colors.white, fontSize: 10),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
