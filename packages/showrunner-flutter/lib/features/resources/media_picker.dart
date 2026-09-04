import 'dart:io';

import 'package:flutter/material.dart';

class MediaPickerScope extends InheritedWidget {
  const MediaPickerScope({
    super.key,
    required this.directory,
    required super.child,
  });

  final Directory directory;

  static Directory? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MediaPickerScope>()?.directory;

  @override
  bool updateShouldNotify(MediaPickerScope oldWidget) =>
      directory.path != oldWidget.directory.path;
}

class MediaPicker extends StatefulWidget {
  const MediaPicker({
    super.key,
    required this.rootDirectory,
    this.mediaFiles,
    this.allowAudio = false,
    this.allowImages = false,
    this.allowVideo = false,
  });

  final Directory rootDirectory;
  final List<File>? mediaFiles;
  final bool allowAudio;
  final bool allowImages;
  final bool allowVideo;

  @override
  State<MediaPicker> createState() => _MediaPickerState();
}

class _MediaPickerState extends State<MediaPicker> {
  final _search = TextEditingController();
  List<File> _files = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.mediaFiles != null) {
      _files = widget.mediaFiles!.where((file) => _allowed(file.path)).toList();
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final files = <File>[];
    if (widget.rootDirectory.existsSync()) {
      for (final entity in widget.rootDirectory.listSync(recursive: true)) {
        if (entity is File && _allowed(entity.path)) files.add(entity);
      }
    }
    files.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    if (!mounted) return;
    setState(() {
      _files = files;
      _loading = false;
    });
  }

  bool _allowed(String path) {
    final extension = path.split('.').last.toLowerCase();
    const audio = {'mp3', 'wav', 'ogg', 'flac', 'm4a'};
    const images = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};
    const video = {'mp4', 'webm', 'mov', 'mkv', 'avi'};
    return (widget.allowAudio && audio.contains(extension)) ||
        (widget.allowImages && images.contains(extension)) ||
        (widget.allowVideo && video.contains(extension));
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.toLowerCase();
    final files = _files
        .where((file) => file.path.toLowerCase().contains(query))
        .toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _search,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Filter media',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 280,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : files.isEmpty
              ? Center(
                  child: Text(
                    _files.isEmpty
                        ? 'No media files found.'
                        : 'No matching media.',
                  ),
                )
              : ListView.builder(
                  itemCount: files.length,
                  itemBuilder: (context, index) {
                    final file = files[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(_iconFor(file.path)),
                      title: Text(
                        file.uri.pathSegments.last,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        file.path,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.of(context).pop(file.path),
                    );
                  },
                ),
        ),
      ],
    );
  }

  IconData _iconFor(String path) {
    final extension = path.split('.').last.toLowerCase();
    if ({'mp3', 'wav', 'ogg', 'flac', 'm4a'}.contains(extension)) {
      return Icons.audiotrack;
    }
    if ({'mp4', 'webm', 'mov', 'mkv', 'avi'}.contains(extension)) {
      return Icons.movie_outlined;
    }
    return Icons.image_outlined;
  }
}

Future<String?> showMediaPicker(
  BuildContext context, {
  required Directory rootDirectory,
  List<File>? mediaFiles,
  bool allowAudio = false,
  bool allowImages = false,
  bool allowVideo = false,
}) => showDialog<String>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Select media'),
    content: MediaPicker(
      rootDirectory: rootDirectory,
      mediaFiles: mediaFiles,
      allowAudio: allowAudio,
      allowImages: allowImages,
      allowVideo: allowVideo,
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
    ],
  ),
);
