import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../services/media_catalog_service.dart';
import '../../services/showrunner_data_service.dart';

class MediaWorkspace extends StatefulWidget {
  const MediaWorkspace({super.key, required this.dataService});

  final ShowRunnerDataService dataService;

  @override
  State<MediaWorkspace> createState() => _MediaWorkspaceState();
}

class _MediaWorkspaceState extends State<MediaWorkspace> {
  final _filterController = TextEditingController();
  late final MediaCatalogService _catalogService;
  late Future<MediaScanResult> _scanFuture;
  String _filter = '';
  bool _draggingFiles = false;

  @override
  void initState() {
    super.initState();
    _catalogService = MediaCatalogService(widget.dataService.userDirectory);
    _filterController.addListener(_onFilterChanged);
    _scanFuture = _catalogService.scan();
  }

  @override
  void dispose() {
    _filterController
      ..removeListener(_onFilterChanged)
      ..dispose();
    super.dispose();
  }

  void _onFilterChanged() {
    final next = _filterController.text.trim().toLowerCase();
    if (next == _filter) return;
    setState(() => _filter = next);
  }

  void _reload({MediaScanMode mode = MediaScanMode.quick}) {
    setState(() => _scanFuture = _catalogService.scan(mode: mode));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<MediaScanResult>(
    future: _scanFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      final files = (snapshot.data?.entries ?? const <MediaFileEntry>[]).where((
        file,
      ) {
        return _filter.isEmpty ||
            file.relativePath.toLowerCase().contains(_filter);
      }).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: Row(
              children: [
                FilledButton.icon(
                  onPressed: _catalogService.openMediaFolder,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Open Media Folder'),
                ),
                const Spacer(),
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: _filterController,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Quick scan',
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Full metadata rescan',
                  onPressed: () => _reload(mode: MediaScanMode.full),
                  icon: const Icon(Icons.manage_search),
                ),
              ],
            ),
          ),
          if (snapshot.hasError)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Unable to load media files: ${snapshot.error}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: DropTarget(
              onDragEntered: (_) => setState(() => _draggingFiles = true),
              onDragExited: (_) => setState(() => _draggingFiles = false),
              onDragDone: _importDroppedFiles,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  border: _draggingFiles
                      ? Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        )
                      : null,
                ),
                child: files.isEmpty
                    ? Center(
                        child: Text(
                          snapshot.hasError
                              ? 'Unable to load media files.'
                              : _filter.isEmpty
                              ? 'No media files found. Drop media files here.'
                              : 'No matching media.',
                        ),
                      )
                    : _MediaTreeView(
                        files: files,
                        onShowInExplorer: _catalogService.showInExplorer,
                        expandFolders: _filter.isNotEmpty,
                      ),
              ),
            ),
          ),
        ],
      );
    },
  );

  Future<void> _importDroppedFiles(DropDoneDetails details) async {
    setState(() => _draggingFiles = false);
    final sources = <File>[];
    void collect(DropItem item) {
      if (item is DropItemDirectory) {
        for (final child in item.children) {
          collect(child);
        }
      } else if (item.path.isNotEmpty) {
        sources.add(File(item.path));
      }
    }

    for (final item in details.files) {
      collect(item);
    }
    final imported = await _catalogService.importFiles(sources);
    if (!mounted) return;
    _reload();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          imported == 0
              ? 'No new supported media files were imported.'
              : 'Imported $imported media file${imported == 1 ? '' : 's'}.',
        ),
      ),
    );
  }
}

final class _MediaFolderNode {
  _MediaFolderNode(this.name, this.path);

  final String name;
  final String path;
  final Map<String, _MediaFolderNode> folders = {};
  final List<MediaFileEntry> files = [];
}

class _MediaTreeView extends StatelessWidget {
  const _MediaTreeView({
    required this.files,
    required this.onShowInExplorer,
    required this.expandFolders,
  });

  final List<MediaFileEntry> files;
  final Future<void> Function(MediaFileEntry entry) onShowInExplorer;
  final bool expandFolders;

  @override
  Widget build(BuildContext context) {
    final root = _MediaFolderNode('', '');
    for (final file in files) {
      final segments = file.relativePath.split('/');
      var folder = root;
      for (var index = 0; index < segments.length - 1; index++) {
        final name = segments[index];
        final path = folder.path.isEmpty ? name : '${folder.path}/$name';
        folder = folder.folders.putIfAbsent(
          name,
          () => _MediaFolderNode(name, path),
        );
      }
      folder.files.add(file);
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: _buildFolderChildren(root),
    );
  }

  List<Widget> _buildFolderChildren(_MediaFolderNode folder) => [
    for (final file in folder.files)
      _MediaFileTile(
        entry: file,
        onShowInExplorer: () => onShowInExplorer(file),
      ),
    for (final child in folder.folders.values)
      ExpansionTile(
        key: PageStorageKey<String>('media-folder:${child.path}'),
        initiallyExpanded: expandFolders,
        leading: const Icon(Icons.folder_outlined),
        title: Text(child.name),
        childrenPadding: const EdgeInsets.only(left: 16),
        children: _buildFolderChildren(child),
      ),
  ];
}

class _MediaFileTile extends StatelessWidget {
  const _MediaFileTile({required this.entry, required this.onShowInExplorer});

  final MediaFileEntry entry;
  final VoidCallback onShowInExplorer;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onSecondaryTap: () => _showContextMenu(context),
    child: ListTile(
      leading: _MediaFilePreview(entry: entry),
      title: Text(entry.relativePath, overflow: TextOverflow.ellipsis),
      subtitle: Text(entry.file.path, overflow: TextOverflow.ellipsis),
      trailing: IconButton(
        tooltip: 'Show in Explorer',
        onPressed: onShowInExplorer,
        icon: const Icon(Icons.folder_open),
      ),
    ),
  );

  Future<void> _showContextMenu(BuildContext context) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(entry.relativePath),
        content: ListTile(
          leading: const Icon(Icons.folder_open),
          title: const Text('Show In Explorer'),
          onTap: () => Navigator.pop(context, 'explore'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (action == 'explore') onShowInExplorer();
  }
}

class _MediaFilePreview extends StatefulWidget {
  const _MediaFilePreview({required this.entry});

  final MediaFileEntry entry;

  @override
  State<_MediaFilePreview> createState() => _MediaFilePreviewState();
}

class _MediaFilePreviewState extends State<_MediaFilePreview> {
  Player? _player;
  bool _loading = false;
  Object? _error;

  @override
  void dispose() {
    final player = _player;
    _player = null;
    if (player != null) {
      player.dispose();
    }
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    final existing = _player;
    if (existing != null) {
      if (existing.state.playing) {
        await existing.pause();
      } else {
        await existing.play();
      }
      if (mounted) setState(() {});
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    final player = Player();
    _player = player;
    try {
      await player.open(
        Media(Uri.file(widget.entry.file.absolute.path).toString()),
        play: true,
      );
      if (mounted) setState(() => _loading = false);
    } catch (error) {
      await player.dispose();
      if (_player == player) _player = null;
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    if (entry.kind == MediaKind.image) {
      return SizedBox.square(
        dimension: 50,
        child: Image.file(
          entry.file,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _iconSurface(context),
        ),
      );
    }

    final player = _player;
    final playing = player?.state.playing ?? false;
    return SizedBox(
      width: 120,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 40,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      tooltip: playing ? 'Pause preview' : 'Play preview',
                      padding: EdgeInsets.zero,
                      onPressed: _togglePlayback,
                      icon: Icon(
                        playing ? Icons.pause : Icons.play_arrow,
                        size: 20,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _DurationLabel(
              player: player,
              error: _error,
              icon: entry.kind == MediaKind.audio
                  ? Icons.audiotrack
                  : Icons.movie_outlined,
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconSurface(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Icon(Icons.image_outlined, color: Colors.white54),
  );
}

class _DurationLabel extends StatelessWidget {
  const _DurationLabel({
    required this.player,
    required this.error,
    required this.icon,
  });

  final Player? player;
  final Object? error;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Tooltip(
        message: '$error',
        child: Icon(
          Icons.error_outline,
          size: 18,
          color: Theme.of(context).colorScheme.error,
        ),
      );
    }
    final currentPlayer = player;
    if (currentPlayer == null) {
      return Icon(icon, size: 18, color: Colors.white54);
    }
    return StreamBuilder<Duration>(
      stream: currentPlayer.stream.duration,
      initialData: currentPlayer.state.duration,
      builder: (context, durationSnapshot) => StreamBuilder<Duration>(
        stream: currentPlayer.stream.position,
        initialData: currentPlayer.state.position,
        builder: (context, positionSnapshot) => Text(
          '${_formatDuration(positionSnapshot.data ?? Duration.zero)} / ${_formatDuration(durationSnapshot.data ?? Duration.zero)}',
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}

String _formatDuration(Duration value) {
  final seconds = value.inSeconds;
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return '$minutes:${remainder.toString().padLeft(2, '0')}';
}
