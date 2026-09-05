import 'package:flutter/material.dart';

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
  late Future<List<MediaFileEntry>> _filesFuture;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _catalogService = MediaCatalogService(widget.dataService.userDirectory);
    _filterController.addListener(_onFilterChanged);
    _filesFuture = _catalogService.discover();
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

  void _reload() {
    setState(() => _filesFuture = _catalogService.discover());
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<MediaFileEntry>>(
    future: _filesFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      final files = (snapshot.data ?? const <MediaFileEntry>[]).where((file) {
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
                  tooltip: 'Refresh media',
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
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
            child: files.isEmpty
                ? Center(
                    child: Text(
                      snapshot.hasError
                          ? 'Unable to load media files.'
                          : _filter.isEmpty
                          ? 'No media files found.'
                          : 'No matching media.',
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: files.length,
                    itemBuilder: (context, index) => _MediaFileTile(
                      entry: files[index],
                      onShowInExplorer: () =>
                          _catalogService.showInExplorer(files[index]),
                    ),
                  ),
          ),
        ],
      );
    },
  );
}

class _MediaFileTile extends StatelessWidget {
  const _MediaFileTile({required this.entry, required this.onShowInExplorer});

  final MediaFileEntry entry;
  final VoidCallback onShowInExplorer;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: SizedBox.square(dimension: 50, child: _preview(context)),
    title: Text(entry.relativePath, overflow: TextOverflow.ellipsis),
    subtitle: Text(entry.file.path, overflow: TextOverflow.ellipsis),
    trailing: IconButton(
      tooltip: 'Show in Explorer',
      onPressed: onShowInExplorer,
      icon: const Icon(Icons.folder_open),
    ),
  );

  Widget _preview(BuildContext context) {
    if (entry.kind == MediaKind.image) {
      return Image.file(
        entry.file,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Icon(_icon, color: Colors.white54),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(_icon, color: Colors.white54),
    );
  }

  IconData get _icon => switch (entry.kind) {
    MediaKind.image => Icons.image_outlined,
    MediaKind.audio => Icons.audiotrack,
    MediaKind.video => Icons.movie_outlined,
  };
}
