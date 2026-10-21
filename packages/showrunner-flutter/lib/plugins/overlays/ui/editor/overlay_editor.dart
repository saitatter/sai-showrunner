import 'package:showrunner_flutter/components/data_inputs/numeric_input_formatter.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:showrunner_flutter/app/app_feedback.dart';
import 'package:showrunner_flutter/app/name_dialog.dart';
import 'package:showrunner_flutter/design_system/tokens/tokens.dart';

import 'package:showrunner_flutter/plugins/obs/overlay_source_service.dart';
import 'package:showrunner_flutter/schema/json.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/features/resources/overlay/overlay_document.dart';
import 'package:showrunner_flutter/features/resources/overlay/overlay_snapping.dart';
import 'package:showrunner_flutter/plugins/overlays/generated_widget_catalog.dart';
import 'package:showrunner_flutter/plugins/overlays/overlay_widget_icons.dart';
import 'package:showrunner_flutter/plugins/overlays/overlay_presence.dart';
import 'package:showrunner_flutter/services/oauth_token.dart';

import 'package:showrunner_flutter/plugins/overlays/ui/editor/overlay_canvas.dart';
import 'package:showrunner_flutter/plugins/overlays/ui/editor/overlay_widget_inspector.dart';
import 'package:showrunner_flutter/plugins/overlays/ui/editor/overlay_widget_presentation.dart';

class OverlayEditorPage extends StatefulWidget {
  const OverlayEditorPage({
    super.key,
    required this.resource,
    required this.onSave,
    this.onDirtyChanged,
    this.onDocumentChanged,
    this.templateSuggestions = const <String>[],
    this.presenceReaderFuture,
    this.obsSourceService,
  });

  final ResourceData resource;
  final Future<void> Function(ResourceData resource) onSave;
  final ValueChanged<bool>? onDirtyChanged;
  final void Function(ResourceData resource, bool dirty)? onDocumentChanged;
  final List<String> templateSuggestions;
  final Future<OverlayPresenceReader?>? presenceReaderFuture;
  final OverlayObsSourceActions? obsSourceService;

  @override
  State<OverlayEditorPage> createState() => _OverlayEditorState();
}

class _OverlayEditorState extends State<OverlayEditorPage> {
  late final TextEditingController _name;
  late final TextEditingController _width;
  late final TextEditingController _height;
  late final TextEditingController _previewSource;
  late final TextEditingController _previewOffsetX;
  late final TextEditingController _previewOffsetY;
  late List<JsonMap> _widgets;
  late OverlayDocument _document;
  late bool _previewEnabled;
  late bool _previewFromObs;
  List<GeneratedOverlayWidget> _overlayWidgetCatalog =
      GeneratedOverlayWidgetCatalog.widgets;
  int? _selectedWidgetIndex;
  int _inspectorPaneFlex = 55;
  bool _dirty = false;
  bool _saving = false;
  int _editRevision = 0;
  OverlayPresenceReader? _presenceReader;
  late OverlayPresence _presence;
  List<ObsConnectionChoice> _obsConnections = const [];
  String? _selectedObsConnectionId;
  OverlayBrowserSourceStatus? _obsSourceStatus;
  String? _obsSourceError;
  bool _obsConnectionsLoading = false;
  bool _obsSourceLoading = false;
  Timer? _obsRefreshDebounce;
  Timer? _presenceTimer;
  final _widgetMenuLink = LayerLink();
  final _widgetMenuAnchorKey = GlobalKey();
  OverlayEntry? _widgetMenuEntry;
  JsonMap? _canvasTransformItem;
  JsonMap _canvasTransformPosition = const {};
  JsonMap _canvasTransformSize = const {};
  Offset _canvasTransformDelta = Offset.zero;
  bool _snapEnabled = true;
  List<double> _verticalGuides = const [];
  List<double> _horizontalGuides = const [];

  @override
  void initState() {
    super.initState();
    final overlay = OverlayResource.fromResource(widget.resource);
    _name = TextEditingController(text: overlay.name);
    _width = TextEditingController(text: '${overlay.width}');
    _height = TextEditingController(text: '${overlay.height}');
    final preview = widget.resource.config['preview'] is Map
        ? Map<String, dynamic>.from(widget.resource.config['preview'] as Map)
        : const <String, dynamic>{};
    _previewEnabled = widget.resource.config['preview'] is Map;
    _previewFromObs = preview['source']?.toString() == 'obs';
    _previewSource = TextEditingController(
      text: _previewFromObs ? '' : '${preview['source'] ?? ''}',
    );
    _previewOffsetX = TextEditingController(text: '${preview['offsetX'] ?? 0}');
    _previewOffsetY = TextEditingController(text: '${preview['offsetY'] ?? 0}');
    _document = OverlayDocument(widget.resource);
    _widgets = _document.initialWidgets
        .map((widget) => <String, dynamic>{...widget})
        .toList();
    _presence = OverlayPresence.disconnected(widget.resource.id);
    unawaited(_loadPresenceReader());
    unawaited(_loadObsConnections());
    _presenceTimer = Timer.periodic(
      const Duration(milliseconds: 2500),
      (_) => unawaited(_refreshPresence()),
    );
    GeneratedOverlayWidgetCatalog.load().then((widgets) {
      if (!mounted) return;
      setState(() => _overlayWidgetCatalog = widgets);
    });
  }

  @override
  void didUpdateWidget(covariant OverlayEditorPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resource.id != widget.resource.id ||
        oldWidget.presenceReaderFuture != widget.presenceReaderFuture) {
      _presenceReader = null;
      _presence = OverlayPresence.disconnected(widget.resource.id);
      unawaited(_loadPresenceReader());
    }
    if (oldWidget.obsSourceService != widget.obsSourceService) {
      _obsConnections = const [];
      _selectedObsConnectionId = null;
      _obsSourceStatus = null;
      unawaited(_loadObsConnections());
    }
  }

  @override
  void dispose() {
    _closeWidgetMenu();
    _presenceTimer?.cancel();
    _obsRefreshDebounce?.cancel();
    _name.dispose();
    _width.dispose();
    _height.dispose();
    _previewSource.dispose();
    _previewOffsetX.dispose();
    _previewOffsetY.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canvasWidth = _canvasDimension(_width, 1920);
    final canvasHeight = _canvasDimension(_height, 1080);

    final inspectorWidth = math.min(
      352.0,
      math.max(280.0, MediaQuery.sizeOf(context).width * .34),
    );
    return Material(
      key: const ValueKey('overlay-editor-root'),
      color: ShowRunnerColors.surfaceB,
      child: Column(
        children: [
          _overlayEditorToolbar(context),
          const Divider(height: 1),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: OverlayCanvas(
                    width: canvasWidth,
                    height: canvasHeight,
                    widgets: _widgets,
                    selectedIndex: _selectedWidgetIndex,
                    catalog: _overlayWidgetCatalog,
                    onTransformStart: _beginCanvasTransform,
                    onTransformEnd: _endCanvasTransform,
                    verticalGuides: _verticalGuides,
                    horizontalGuides: _horizontalGuides,
                    onSelect: (index) =>
                        setState(() => _selectedWidgetIndex = index),
                    onDeselect: () => setState(() {
                      _selectedWidgetIndex = null;
                      _verticalGuides = const [];
                      _horizontalGuides = const [];
                    }),
                    onMove: (index, delta, tolerance) => _moveWidgetOnCanvas(
                      index,
                      delta,
                      canvasWidth,
                      canvasHeight,
                      tolerance,
                    ),
                    onResize: (index, handle, delta, tolerance) =>
                        _resizeWidgetOnCanvas(
                          index,
                          handle,
                          delta,
                          canvasWidth,
                          canvasHeight,
                          tolerance,
                        ),
                  ),
                ),
                const VerticalDivider(width: 1),
                SizedBox(
                  key: const ValueKey('overlay-widget-sidebar'),
                  width: inspectorWidth,
                  child: Column(
                    children: [
                      Expanded(
                        flex: _inspectorPaneFlex,
                        child: KeyedSubtree(
                          key: const ValueKey('overlay-widget-inspector-pane'),
                          child: Material(
                            color: const Color(0xff202020),
                            child: _overlayInspector(context),
                          ),
                        ),
                      ),
                      MouseRegion(
                        cursor: SystemMouseCursors.resizeUpDown,
                        child: GestureDetector(
                          key: const ValueKey('overlay-inspector-splitter'),
                          behavior: HitTestBehavior.opaque,
                          onVerticalDragUpdate: (details) {
                            setState(() {
                              _inspectorPaneFlex =
                                  (_inspectorPaneFlex +
                                          (details.delta.dy / 8).round())
                                      .clamp(25, 75)
                                      .toInt();
                            });
                          },
                          child: SizedBox(
                            height: 7,
                            child: Center(
                              child: Divider(
                                height: 1,
                                thickness: 1,
                                color: Theme.of(
                                  context,
                                ).colorScheme.outlineVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 100 - _inspectorPaneFlex,
                        child: KeyedSubtree(
                          key: const ValueKey('overlay-widget-list-pane'),
                          child: _overlayWidgetList(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _previewEnabled
                        ? 'Preview enabled'
                        : 'No live preview configured',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                FilledButton(
                  onPressed: _saving
                      ? null
                      : () async {
                          await _saveOverlay();
                        },
                  child: Text(_saving ? 'Saving…' : 'Save'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _snapshotScheduled = false;
  void _markDirty() {
    _editRevision++;
    if (!_snapshotScheduled && widget.onDocumentChanged != null) {
      _snapshotScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _snapshotScheduled = false;
        if (mounted) widget.onDocumentChanged?.call(_snapshot(), _dirty);
      });
    }
    if (!_dirty) {
      _dirty = true;
      widget.onDirtyChanged?.call(true);
    }
  }

  void _clearDirty() {
    if (_dirty) {
      _dirty = false;
      widget.onDirtyChanged?.call(false);
    }
  }

  Widget _overlayEditorToolbar(BuildContext context) => Material(
    key: const ValueKey('overlay-editor-toolbar'),
    color: ShowRunnerColors.surfaceB,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Icon(Icons.layers_outlined),
          IconButton(
            key: const ValueKey('overlay-snap-toggle'),
            tooltip: 'Snap to guides (hold Shift to bypass)',
            isSelected: _snapEnabled,
            selectedIcon: const Icon(Icons.grid_on),
            icon: const Icon(Icons.grid_off),
            onPressed: () => setState(() {
              _snapEnabled = !_snapEnabled;
              _verticalGuides = const [];
              _horizontalGuides = const [];
            }),
          ),
          const Text(
            'Edit overlay',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          SizedBox(
            width: 180,
            child: TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Overlay name',
                isDense: true,
              ),
              onChanged: (_) => _markDirty(),
            ),
          ),
          if (widget.obsSourceService != null) ...[
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                key: const ValueKey('overlay-obs-connection-selector'),
                initialValue:
                    _obsConnections.any(
                      (connection) => connection.id == _selectedObsConnectionId,
                    )
                    ? _selectedObsConnectionId
                    : null,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'OBS Connection',
                  isDense: true,
                  suffixIcon: _obsConnectionsLoading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
                hint: const Text('Select OBS Connection'),
                items: [
                  for (final connection in _obsConnections)
                    DropdownMenuItem(
                      value: connection.id,
                      child: Text(
                        connection.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _obsConnectionsLoading ? null : _selectObsConnection,
              ),
            ),
            _overlayObsSourceControl(context),
          ],
          SizedBox(
            width: 86,
            child: TextField(
              controller: _width,
              inputFormatters: const [
                NumericInputFormatter(decimal: false, signed: false),
              ],
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Width',
                suffixText: 'px',
                isDense: true,
              ),
              onChanged: (_) {
                _markDirty();
                setState(() {});
                _scheduleObsSourceRefresh();
              },
            ),
          ),
          SizedBox(
            width: 86,
            child: TextField(
              controller: _height,
              inputFormatters: const [
                NumericInputFormatter(decimal: false, signed: false),
              ],
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Height',
                suffixText: 'px',
                isDense: true,
              ),
              onChanged: (_) {
                _markDirty();
                setState(() {});
                _scheduleObsSourceRefresh();
              },
            ),
          ),
          _sizePreset('1080p', 1920, 1080),
          _sizePreset('1440p', 2560, 1440),
          _sizePreset('4K', 3840, 2160),
          _sizePreset('Vertical', 1080, 1920),
          IconButton(
            tooltip: 'Preview settings',
            onPressed: () => _showPreviewSettings(context),
            icon: const Icon(Icons.image_outlined),
          ),
        ],
      ),
    ),
  );

  Widget _overlayObsSourceControl(BuildContext context) {
    final selected = _selectedObsConnection;
    final status = _obsSourceStatus;
    final service = widget.obsSourceService;
    if (service == null) return const SizedBox.shrink();
    if (selected == null) {
      return Tooltip(
        message: 'Select an OBS connection to manage its Browser Source.',
        child: OutlinedButton.icon(
          onPressed: null,
          icon: const Icon(Icons.link_off),
          label: const Text('Select OBS Connection'),
        ),
      );
    }
    if (_obsSourceLoading) {
      return const SizedBox(
        width: 42,
        height: 42,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_obsSourceError != null || status?.connected != true) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: _obsSourceError ?? 'OBS connection has not been checked.',
            child: Icon(
              Icons.cloud_off_outlined,
              size: 18,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
          const SizedBox(width: 6),
          if (selected.isLocal)
            OutlinedButton.icon(
              key: const ValueKey('overlay-open-obs'),
              onPressed: () => unawaited(_openObs()),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open OBS'),
            )
          else
            Tooltip(
              message: 'ShowRunner cannot launch OBS on a remote computer.',
              child: const Chip(label: Text('Remote OBS')),
            ),
          IconButton(
            key: const ValueKey('overlay-check-obs'),
            tooltip: 'Check OBS connection',
            onPressed: () => unawaited(_refreshObsSource()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      );
    }
    if (status!.needsCreate) {
      return FilledButton.icon(
        key: const ValueKey('overlay-create-browser-source'),
        onPressed: () => unawaited(_createObsBrowserSource()),
        icon: const Icon(Icons.add),
        label: const Text('Create Source'),
      );
    }
    if (status.needsFix) {
      return FilledButton.tonalIcon(
        key: const ValueKey('overlay-fix-browser-source'),
        onPressed: () => unawaited(_fixObsBrowserSource()),
        icon: const Icon(Icons.build_outlined),
        label: const Text('Fix OBS Source'),
      );
    }
    return Tooltip(
      message: 'This Browser Source is set to the current overlay.',
      child: Chip(
        key: const ValueKey('overlay-browser-source-ready'),
        avatar: const Icon(Icons.web_asset_outlined, size: 18),
        label: Text(status.sourceName ?? 'OBS source ready'),
      ),
    );
  }

  ObsConnectionChoice? get _selectedObsConnection {
    final id = _selectedObsConnectionId;
    if (id == null) return null;
    return _obsConnections
        .where((connection) => connection.id == id)
        .firstOrNull;
  }

  Future<void> _loadObsConnections() async {
    final service = widget.obsSourceService;
    if (service == null) return;
    setState(() => _obsConnectionsLoading = true);
    try {
      final connections = await service.listConnections();
      final defaultId = await service.defaultConnectionId();
      if (!mounted || !identical(service, widget.obsSourceService)) return;
      final selectedId =
          connections.any((connection) => connection.id == defaultId)
          ? defaultId
          : null;
      setState(() {
        _obsConnections = connections;
        _selectedObsConnectionId = selectedId;
        _obsConnectionsLoading = false;
      });
      if (selectedId != null) unawaited(_refreshObsSource());
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _obsConnections = const [];
        _obsConnectionsLoading = false;
        _obsSourceError = '$error';
      });
    }
  }

  void _selectObsConnection(String? id) {
    setState(() {
      _selectedObsConnectionId = id;
      _obsSourceStatus = null;
      _obsSourceError = null;
    });
    if (id != null) unawaited(_refreshObsSource());
  }

  Future<int> _overlayHttpPort() async {
    var reader = _presenceReader;
    final future = widget.presenceReaderFuture;
    if (reader == null && future != null) {
      try {
        reader = await future;
        if (mounted && identical(widget.presenceReaderFuture, future)) {
          _presenceReader = reader;
        }
      } on Object {
        // The editor remains available when the overlay runtime is offline.
      }
    }
    final url = reader?.browserSourceUrl(widget.resource.id);
    return Uri.tryParse(url ?? '')?.port ?? 8181;
  }

  void _scheduleObsSourceRefresh() {
    if (_selectedObsConnectionId == null) return;
    _obsRefreshDebounce?.cancel();
    _obsRefreshDebounce = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_refreshObsSource()),
    );
  }

  Future<void> _refreshObsSource() async {
    final service = widget.obsSourceService;
    final connectionId = _selectedObsConnectionId;
    if (service == null || connectionId == null) return;
    setState(() {
      _obsSourceLoading = true;
      _obsSourceError = null;
    });
    try {
      final status = await service.inspect(
        connectionId: connectionId,
        overlayId: widget.resource.id,
        width: _canvasDimension(_width, 1920),
        height: _canvasDimension(_height, 1080),
        port: await _overlayHttpPort(),
      );
      if (!mounted || connectionId != _selectedObsConnectionId) return;
      setState(() => _obsSourceStatus = status);
    } on Object catch (error) {
      if (!mounted || connectionId != _selectedObsConnectionId) return;
      setState(() {
        _obsSourceStatus = null;
        _obsSourceError = '$error';
      });
    } finally {
      if (mounted && connectionId == _selectedObsConnectionId) {
        setState(() => _obsSourceLoading = false);
      }
    }
  }

  Future<void> _openObs() async {
    final service = widget.obsSourceService;
    final connectionId = _selectedObsConnectionId;
    if (service == null || connectionId == null) return;
    try {
      final opened = await service.openObs(connectionId);
      if (!mounted) return;
      showShowRunnerFeedback(
        context,
        opened
            ? 'Opening OBS Studio.'
            : 'Could not find OBS. Check the OBS install path in its connection settings.',
        severity: opened
            ? ShowRunnerFeedbackSeverity.success
            : ShowRunnerFeedbackSeverity.warning,
      );
    } on Object catch (error) {
      if (!mounted) return;
      showShowRunnerFeedback(
        context,
        'Could not open OBS: $error',
        severity: ShowRunnerFeedbackSeverity.error,
      );
    }
  }

  Future<void> _createObsBrowserSource() async {
    final service = widget.obsSourceService;
    final connectionId = _selectedObsConnectionId;
    if (service == null || connectionId == null) return;
    final sourceName = await showShowRunnerNameDialog(
      context,
      title: 'Create Browser Source',
      initialName:
          '${_name.text.trim().isEmpty ? 'Overlay' : _name.text.trim()} Browser Source',
    );
    if (sourceName == null || !mounted) return;
    setState(() => _obsSourceLoading = true);
    try {
      await service.createBrowserSource(
        connectionId: connectionId,
        overlayId: widget.resource.id,
        sourceName: sourceName,
        width: _canvasDimension(_width, 1920),
        height: _canvasDimension(_height, 1080),
        port: await _overlayHttpPort(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await _refreshObsSource();
    } on Object catch (error) {
      if (!mounted) return;
      showShowRunnerFeedback(
        context,
        'Could not create OBS Browser Source: $error',
        severity: ShowRunnerFeedbackSeverity.error,
      );
      setState(() => _obsSourceLoading = false);
    }
  }

  Future<void> _fixObsBrowserSource() async {
    final service = widget.obsSourceService;
    final connectionId = _selectedObsConnectionId;
    final sourceName = _obsSourceStatus?.sourceName;
    if (service == null || connectionId == null || sourceName == null) return;
    setState(() => _obsSourceLoading = true);
    try {
      await service.fixBrowserSource(
        connectionId: connectionId,
        overlayId: widget.resource.id,
        sourceName: sourceName,
        width: _canvasDimension(_width, 1920),
        height: _canvasDimension(_height, 1080),
        port: await _overlayHttpPort(),
      );
      await _refreshObsSource();
    } on Object catch (error) {
      if (!mounted) return;
      showShowRunnerFeedback(
        context,
        'Could not update OBS Browser Source: $error',
        severity: ShowRunnerFeedbackSeverity.error,
      );
      setState(() => _obsSourceLoading = false);
    }
  }

  Widget _overlayInspector(BuildContext context) {
    final index = _selectedWidgetIndex;
    if (index == null || index < 0 || index >= _widgets.length) {
      return const Center(child: Text('Select a widget to edit it.'));
    }
    final selected = _widgets[index];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
      child: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: InputDecorationTheme(
            filled: false,
            isDense: true,
            floatingLabelBehavior: FloatingLabelBehavior.always,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(5)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: BorderSide(color: const Color(0xff616161)),
            ),
          ),
        ),
        child: OverlayWidgetInspector(
          key: ValueKey('overlay-widget-inspector-${selected['id']}'),
          widgetConfig: selected,
          onChanged: (key, value) {
            _markDirty();
            setState(() => selected[key] = value);
          },
          catalog: _overlayWidgetCatalog,
          templateSuggestions: widget.templateSuggestions,
        ),
      ),
    );
  }

  Widget _overlayWidgetList(BuildContext context) {
    // ReorderableListView creates an overlay entry while dragging. Keeping it
    // below a LayoutBuilder can mutate that builder during performLayout on
    // desktop mouse drags, which trips Flutter's render-object layout guard.
    // The editor is hosted in the app workspace, so use the window height to
    // decide whether the optional source card fits instead of measuring here.
    final showBrowserSourceCard = MediaQuery.sizeOf(context).height >= 900;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Widgets',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              if (!showBrowserSourceCard)
                IconButton(
                  tooltip: 'Browser Source status and URL',
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('OBS Browser Source'),
                      content: _overlayBrowserSourceCard(context),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  ),
                  icon: Icon(
                    _presence.connected
                        ? Icons.wifi_tethering
                        : Icons.wifi_tethering_off,
                  ),
                ),
              CompositedTransformTarget(
                key: _widgetMenuAnchorKey,
                link: _widgetMenuLink,
                child: IconButton(
                  tooltip: 'Add widget',
                  onPressed: _toggleWidgetMenu,
                  icon: const Icon(Icons.add),
                ),
              ),
            ],
          ),
          Expanded(
            child: _widgets.isEmpty
                ? const Center(child: Text('No widgets defined.'))
                : ReorderableListView.builder(
                    key: const ValueKey('overlay-widget-reorder-list'),
                    buildDefaultDragHandles: false,
                    itemCount: _widgets.length,
                    onReorderItem: _reorderWidgets,
                    itemBuilder: (context, index) {
                      final item = _widgets[index];
                      final selected = index == _selectedWidgetIndex;
                      return Material(
                        key: ValueKey(
                          'overlay-widget-row-${item['id'] ?? index}',
                        ),
                        color: selected
                            ? Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: .14)
                            : Colors.transparent,
                        child: InkWell(
                          onTap: () =>
                              setState(() => _selectedWidgetIndex = index),
                          child: SizedBox(
                            height: 58,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: LayoutBuilder(
                                builder: (context, constraints) => Row(
                                  children: [
                                    Tooltip(
                                      message:
                                          'Drag to reorder (or use Widget actions)',
                                      child: MouseRegion(
                                        cursor: SystemMouseCursors.grab,
                                        child: ReorderableDragStartListener(
                                          index: index,
                                          child: const SizedBox(
                                            width: 36,
                                            height: 48,
                                            child: Center(
                                              child: Icon(
                                                Icons.drag_handle,
                                                size: 28,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    KeyedSubtree(
                                      key: ValueKey(
                                        'overlay-widget-row-icon-${item['id']}',
                                      ),
                                      child: _widgetListIcon(item),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _OverlayLayerTitle(
                                            key: ValueKey(
                                              'overlay-layer-title-${item['id']}',
                                            ),
                                            widgetId: item['id'].toString(),
                                            name:
                                                OverlayWidgetPresentation.title(
                                                  item,
                                                  _overlayWidgetCatalog,
                                                ),
                                            onSelected: () => setState(
                                              () =>
                                                  _selectedWidgetIndex = index,
                                            ),
                                            onRenamed: (name) {
                                              setState(
                                                () => item['name'] = name,
                                              );
                                              _markDirty();
                                            },
                                          ),
                                          Text(
                                            _widgetListSubtitle(item),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      key: ValueKey(
                                        'overlay-widget-visibility-${item['id']}',
                                      ),
                                      tooltip: item['visible'] == false
                                          ? 'Show widget'
                                          : 'Hide widget',
                                      visualDensity: VisualDensity.compact,
                                      constraints:
                                          const BoxConstraints.tightFor(
                                            width: 30,
                                            height: 30,
                                          ),
                                      padding: EdgeInsets.zero,
                                      onPressed: () =>
                                          _toggleWidgetFlag(index, 'visible'),
                                      icon: Icon(
                                        item['visible'] == false
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        size: 18,
                                      ),
                                    ),
                                    IconButton(
                                      key: ValueKey(
                                        'overlay-widget-lock-${item['id']}',
                                      ),
                                      tooltip: item['locked'] == true
                                          ? 'Unlock widget'
                                          : 'Lock widget',
                                      visualDensity: VisualDensity.compact,
                                      constraints:
                                          const BoxConstraints.tightFor(
                                            width: 30,
                                            height: 30,
                                          ),
                                      padding: EdgeInsets.zero,
                                      onPressed: () =>
                                          _toggleWidgetFlag(index, 'locked'),
                                      icon: Icon(
                                        item['locked'] == true
                                            ? Icons.lock_outline
                                            : Icons.lock_open_outlined,
                                        size: 18,
                                      ),
                                    ),
                                    if (constraints.maxWidth >= 280) ...[
                                      IconButton(
                                        key: ValueKey(
                                          'overlay-widget-list-move-up-${item['id']}',
                                        ),
                                        tooltip: 'Move up',
                                        visualDensity: VisualDensity.compact,
                                        constraints:
                                            const BoxConstraints.tightFor(
                                              width: 28,
                                              height: 28,
                                            ),
                                        padding: EdgeInsets.zero,
                                        onPressed: index == 0
                                            ? null
                                            : () => _moveWidget(index, -1),
                                        icon: const Icon(
                                          Icons.keyboard_arrow_up,
                                          size: 18,
                                        ),
                                      ),
                                      IconButton(
                                        key: ValueKey(
                                          'overlay-widget-list-move-down-${item['id']}',
                                        ),
                                        tooltip: 'Move down',
                                        visualDensity: VisualDensity.compact,
                                        constraints:
                                            const BoxConstraints.tightFor(
                                              width: 28,
                                              height: 28,
                                            ),
                                        padding: EdgeInsets.zero,
                                        onPressed: index == _widgets.length - 1
                                            ? null
                                            : () => _moveWidget(index, 1),
                                        icon: const Icon(
                                          Icons.keyboard_arrow_down,
                                          size: 18,
                                        ),
                                      ),
                                    ],
                                    PopupMenuButton<String>(
                                      key: ValueKey(
                                        'overlay-widget-actions-${item['id']}',
                                      ),
                                      tooltip: 'Widget actions',
                                      padding: EdgeInsets.zero,
                                      iconSize: 18,
                                      onSelected: (action) {
                                        switch (action) {
                                          case 'rename':
                                            _renameWidget(index);
                                            break;
                                          case 'up':
                                            _moveWidget(index, -1);
                                            break;
                                          case 'down':
                                            _moveWidget(index, 1);
                                            break;
                                          case 'delete':
                                            _deleteWidget(index);
                                            break;
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                          value: 'rename',
                                          child: Text('Rename'),
                                        ),
                                        PopupMenuItem(
                                          value: 'up',
                                          enabled: index > 0,
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.keyboard_arrow_up,
                                                size: 18,
                                              ),
                                              SizedBox(width: 8),
                                              Text('Move up'),
                                            ],
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'down',
                                          enabled: index < _widgets.length - 1,
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.keyboard_arrow_down,
                                                size: 18,
                                              ),
                                              SizedBox(width: 8),
                                              Text('Move down'),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuDivider(),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (showBrowserSourceCard) ...[
            const Divider(height: 1),
            _overlayBrowserSourceCard(context),
          ],
        ],
      ),
    );
  }

  Widget _overlayBrowserSourceCard(BuildContext context) {
    final connected = _presence.connected;
    final url =
        _presenceReader?.browserSourceUrl(widget.resource.id) ??
        Uri(
          scheme: 'http',
          host: 'localhost',
          port: 8181,
          pathSegments: ['overlays', widget.resource.id],
        ).toString();
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Tooltip(
                message: 'OBS Browser Source',
                child: Icon(
                  connected ? Icons.wifi_tethering : Icons.wifi_tethering_off,
                  size: 15,
                  color: connected
                      ? const Color(0xff54d98c)
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                connected
                    ? 'Connected (${_presence.subscribers})'
                    : 'Disconnected',
                key: const ValueKey('overlay-browser-source-status'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: connected ? const Color(0xff54d98c) : null,
                ),
              ),
              IconButton(
                tooltip: 'Copy Browser Source URL',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                padding: EdgeInsets.zero,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: url));
                  if (context.mounted) {
                    showShowRunnerFeedback(
                      context,
                      'Browser Source URL copied.',
                      severity: ShowRunnerFeedbackSeverity.success,
                    );
                  }
                },
                icon: const Icon(Icons.copy, size: 15),
              ),
              IconButton(
                tooltip: 'Open Browser Source URL',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                padding: EdgeInsets.zero,
                onPressed: () async {
                  try {
                    await openOAuthUrlInBrowser(Uri.parse(url));
                  } on Object catch (error) {
                    if (context.mounted) {
                      showShowRunnerFeedback(
                        context,
                        'Could not open Browser Source URL: $error',
                        severity: ShowRunnerFeedbackSeverity.error,
                      );
                    }
                  }
                },
                icon: const Icon(Icons.open_in_new, size: 15),
              ),
            ],
          ),
          SelectableText(
            url,
            key: const ValueKey('overlay-browser-source-url'),
            maxLines: 1,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Future<void> _loadPresenceReader() async {
    final future = widget.presenceReaderFuture;
    if (future == null) return;
    try {
      final reader = await future;
      if (!mounted || !identical(widget.presenceReaderFuture, future)) return;
      _presenceReader = reader;
      await _refreshPresence();
    } on Object {
      // Overlay editing remains available even if the runtime is unavailable.
    }
  }

  Future<void> _refreshPresence() async {
    final reader = _presenceReader;
    if (reader == null) return;
    try {
      final presence = await reader.getPresence(widget.resource.id);
      if (!mounted || presence == _presence) return;
      setState(() => _presence = presence);
    } on Object {
      if (!mounted) return;
      final disconnected = OverlayPresence.disconnected(widget.resource.id);
      if (_presence != disconnected) {
        setState(() => _presence = disconnected);
      }
    }
  }

  Future<void> _showPreviewSettings(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Preview settings'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enable preview'),
                  value: _previewEnabled,
                  onChanged: (value) {
                    _markDirty();
                    setState(() => _previewEnabled = value);
                    setDialogState(() {});
                  },
                ),
                if (_previewEnabled) ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Preview OBS output'),
                    value: _previewFromObs,
                    onChanged: (value) {
                      _markDirty();
                      setState(() => _previewFromObs = value);
                      setDialogState(() {});
                    },
                  ),
                  if (!_previewFromObs)
                    TextField(
                      controller: _previewSource,
                      decoration: const InputDecoration(
                        labelText: 'Preview image',
                        hintText: 'Optional PNG/JPG/BMP/WebP path',
                      ),
                      onChanged: (_) => _markDirty(),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _previewOffsetX,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          inputFormatters: const [NumericInputFormatter()],
                          decoration: const InputDecoration(
                            labelText: 'Offset X',
                          ),
                          onChanged: (_) => _markDirty(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _previewOffsetY,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          inputFormatters: const [NumericInputFormatter()],
                          decoration: const InputDecoration(
                            labelText: 'Offset Y',
                          ),
                          onChanged: (_) => _markDirty(),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  ResourceData _snapshot() => _document.snapshot(
    name: _name.text.trim(),
    width: _canvasDimension(_width, 1920),
    height: _canvasDimension(_height, 1080),
    widgets: _widgets,
    preview: _previewEnabled
        ? {
            'offsetX': num.tryParse(_previewOffsetX.text) ?? 0,
            'offsetY': num.tryParse(_previewOffsetY.text) ?? 0,
            if (_previewFromObs)
              'source': 'obs'
            else if (_previewSource.text.trim().isNotEmpty)
              'source': _previewSource.text.trim(),
          }
        : null,
  );

  Future<void> _saveOverlay() async {
    if (_saving) return;
    final revision = _editRevision;
    final snapshot = _snapshot();
    setState(() => _saving = true);
    try {
      await widget.onSave(snapshot);
      if (!mounted) return;
      if (revision == _editRevision) _clearDirty();
      widget.onDocumentChanged?.call(_snapshot(), _dirty);
    } on Object catch (error) {
      if (!mounted) return;
      showShowRunnerFeedback(
        context,
        'Could not save overlay: $error',
        severity: ShowRunnerFeedbackSeverity.error,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  int _canvasDimension(TextEditingController controller, int fallback) {
    final value = int.tryParse(controller.text);
    return value != null && value > 0 ? value : fallback;
  }

  void _beginCanvasTransform(int index) {
    if (index < 0 || index >= _widgets.length) return;
    final item = _widgets[index];
    _canvasTransformItem = item;
    _canvasTransformPosition = item['position'] is Map
        ? Map<String, dynamic>.from(item['position'] as Map)
        : {};
    _canvasTransformSize = item['size'] is Map
        ? Map<String, dynamic>.from(item['size'] as Map)
        : {};
    _canvasTransformDelta = Offset.zero;
  }

  void _endCanvasTransform() {
    _canvasTransformItem = null;
    _canvasTransformDelta = Offset.zero;
    if (mounted &&
        (_verticalGuides.isNotEmpty || _horizontalGuides.isNotEmpty)) {
      setState(() {
        _verticalGuides = const [];
        _horizontalGuides = const [];
      });
    }
  }

  Rect _snapBounds(
    int index,
    Rect bounds,
    int width,
    int height,
    double tolerance, {
    OverlayResizeHandle? handle,
  }) {
    final result = _snapEnabled && !HardwareKeyboard.instance.isShiftPressed
        ? snapOverlayBounds(
            bounds: bounds,
            stage: Size(width.toDouble(), height.toDouble()),
            tolerance: tolerance,
            peers: [
              for (var peerIndex = 0; peerIndex < _widgets.length; peerIndex++)
                if (peerIndex != index &&
                    _widgets[peerIndex]['visible'] != false)
                  _widgetBounds(_widgets[peerIndex]),
            ],
            resize: handle != null,
            left: handle?.movesLeft ?? false,
            right: handle?.movesRight ?? false,
            top: handle?.movesTop ?? false,
            bottom: handle?.movesBottom ?? false,
          )
        : OverlaySnapResult(bounds, const [], const []);
    _verticalGuides = result.vertical;
    _horizontalGuides = result.horizontal;
    return result.bounds;
  }

  Rect _widgetBounds(JsonMap item) {
    final position = item['position'] as Map? ?? const {};
    final size = item['size'] as Map? ?? const {};
    return Rect.fromLTWH(
      (position['x'] as num?)?.toDouble() ?? 0,
      (position['y'] as num?)?.toDouble() ?? 0,
      (size['width'] as num?)?.toDouble() ?? 320,
      (size['height'] as num?)?.toDouble() ?? 80,
    );
  }

  Offset _accumulateCanvasTransform(int index, Offset delta) {
    if (!identical(_canvasTransformItem, _widgets[index])) {
      _beginCanvasTransform(index);
    }
    return _canvasTransformDelta += delta;
  }

  void _moveWidgetOnCanvas(
    int index,
    Offset delta,
    int canvasWidth,
    int canvasHeight,
    double tolerance,
  ) {
    if (index < 0 || index >= _widgets.length) return;
    final item = _widgets[index];
    if (item['locked'] == true || item['visible'] == false) return;
    final accumulated = _accumulateCanvasTransform(index, delta);
    final position = _canvasTransformPosition;
    final size = _canvasTransformSize;
    final width = (size['width'] as num?)?.toDouble() ?? 320;
    final height = (size['height'] as num?)?.toDouble() ?? 80;
    final x = ((position['x'] as num?)?.toDouble() ?? 0) + accumulated.dx;
    final y = ((position['y'] as num?)?.toDouble() ?? 0) + accumulated.dy;
    setState(() {
      final snapped = _snapBounds(
        index,
        Rect.fromLTWH(
          x.clamp(0, math.max(0, canvasWidth - width).floor()).roundToDouble(),
          y
              .clamp(0, math.max(0, canvasHeight - height).floor())
              .roundToDouble(),
          width,
          height,
        ),
        canvasWidth,
        canvasHeight,
        tolerance,
      );
      item['position'] = {'x': snapped.left.round(), 'y': snapped.top.round()};
    });
    _markDirty();
  }

  void _resizeWidgetOnCanvas(
    int index,
    OverlayResizeHandle handle,
    Offset delta,
    int canvasWidth,
    int canvasHeight,
    double tolerance,
  ) {
    if (index < 0 || index >= _widgets.length) return;
    final item = _widgets[index];
    if (item['locked'] == true || item['visible'] == false) return;
    final accumulated = _accumulateCanvasTransform(index, delta);
    final position = _canvasTransformPosition;
    final size = _canvasTransformSize;
    final oldX = (position['x'] as num?)?.toDouble() ?? 0;
    final oldY = (position['y'] as num?)?.toDouble() ?? 0;
    final oldWidth = (size['width'] as num?)?.toDouble() ?? 320;
    final oldHeight = (size['height'] as num?)?.toDouble() ?? 80;
    const minimum = 24.0;
    var left = oldX;
    var top = oldY;
    var right = oldX + oldWidth;
    var bottom = oldY + oldHeight;

    if (handle.movesLeft) left += accumulated.dx;
    if (handle.movesRight) right += accumulated.dx;
    if (handle.movesTop) top += accumulated.dy;
    if (handle.movesBottom) bottom += accumulated.dy;

    if (right - left < minimum) {
      if (handle.movesLeft) {
        left = right - minimum;
      } else {
        right = left + minimum;
      }
    }
    if (bottom - top < minimum) {
      if (handle.movesTop) {
        top = bottom - minimum;
      } else {
        bottom = top + minimum;
      }
    }
    if (left < 0) left = 0;
    if (top < 0) top = 0;
    if (right > canvasWidth) right = canvasWidth.toDouble();
    if (bottom > canvasHeight) bottom = canvasHeight.toDouble();
    if (right - left < minimum) left = math.max(0, right - minimum);
    if (bottom - top < minimum) top = math.max(0, bottom - minimum);

    setState(() {
      final snapped = _snapBounds(
        index,
        Rect.fromLTRB(
          left.roundToDouble(),
          top.roundToDouble(),
          right.roundToDouble(),
          bottom.roundToDouble(),
        ),
        canvasWidth,
        canvasHeight,
        tolerance,
        handle: handle,
      );
      item['position'] = {'x': snapped.left.round(), 'y': snapped.top.round()};
      item['size'] = {
        'width': snapped.width.round(),
        'height': snapped.height.round(),
      };
    });
    _markDirty();
  }

  void _deleteWidget(int index) {
    if (index < 0 || index >= _widgets.length) return;
    setState(() {
      _widgets.removeAt(index);
      if (_widgets.isEmpty) {
        _selectedWidgetIndex = null;
      } else {
        _selectedWidgetIndex = math.min(index, _widgets.length - 1);
      }
    });
    _markDirty();
  }

  void _toggleWidgetMenu() {
    if (_widgetMenuEntry != null) {
      _closeWidgetMenu();
      return;
    }
    final renderBox =
        _widgetMenuAnchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final anchorOffset = renderBox.localToGlobal(Offset.zero);
    final availableHeight =
        MediaQuery.sizeOf(context).height -
        anchorOffset.dy -
        renderBox.size.height -
        8;
    final menuHeight = math.min(420.0, math.max(108.0, availableHeight));
    final overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _closeWidgetMenu,
              child: const SizedBox.expand(),
            ),
          ),
          CompositedTransformFollower(
            link: _widgetMenuLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 4),
            child: _OverlayWidgetMenu(
              catalog: _overlayWidgetCatalog,
              height: menuHeight,
              onSelected: (definition) {
                _addWidget(definition);
                _closeWidgetMenu();
              },
            ),
          ),
        ],
      ),
    );
    _widgetMenuEntry = entry;
    overlay.insert(entry);
  }

  void _closeWidgetMenu() {
    final entry = _widgetMenuEntry;
    _widgetMenuEntry = null;
    entry?.remove();
  }

  Widget _sizePreset(String label, int width, int height) => OutlinedButton(
    onPressed: () {
      _markDirty();
      setState(() {
        _width.text = '$width';
        _height.text = '$height';
      });
      _scheduleObsSourceRefresh();
    },
    child: Text(label),
  );

  void _addWidget(GeneratedOverlayWidget definition) {
    final widgetConfig = definition.createWidget(
      canvasWidth: _canvasDimension(_width, 1920),
      canvasHeight: _canvasDimension(_height, 1080),
    );
    final baseName = definition.name;
    final names = _widgets
        .map((widget) => widget['name']?.toString())
        .whereType<String>()
        .toSet();
    var name = baseName;
    for (var suffix = 1; names.contains(name); suffix++) {
      name = '$baseName $suffix';
    }
    widgetConfig['name'] = name;
    setState(() {
      _widgets.add(widgetConfig);
      _selectedWidgetIndex = _widgets.length - 1;
    });
    _markDirty();
  }

  void _moveWidget(int index, int delta) {
    _moveWidgetTo(index, index + delta);
  }

  void _reorderWidgets(int oldIndex, int newIndex) {
    // onReorderItem reports the final index after the removal adjustment.
    _moveWidgetTo(oldIndex, newIndex);
  }

  void _moveWidgetTo(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 || oldIndex >= _widgets.length) return;
    if (newIndex < 0 || newIndex >= _widgets.length) return;
    final selectedIndex = _selectedWidgetIndex;
    final selectedWidget =
        selectedIndex != null &&
            selectedIndex >= 0 &&
            selectedIndex < _widgets.length
        ? _widgets[selectedIndex]
        : null;
    setState(() {
      final movedWidget = _widgets.removeAt(oldIndex);
      _widgets.insert(newIndex, movedWidget);
      _selectedWidgetIndex = selectedWidget == null
          ? null
          : _widgets.indexOf(selectedWidget);
    });
    _markDirty();
  }

  void _toggleWidgetFlag(int index, String key) {
    if (index < 0 || index >= _widgets.length) return;
    setState(() {
      _widgets[index][key] = _widgets[index][key] != true;
    });
    _markDirty();
  }

  Future<void> _renameWidget(int index) async {
    if (index < 0 || index >= _widgets.length) return;
    final widgetConfig = _widgets[index];
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _OverlayWidgetRenameDialog(
        widgetId: widgetConfig['id']?.toString() ?? '$index',
        name: widgetConfig['name']?.toString() ?? '',
      ),
    );
    final normalizedName = name?.trim();
    if (normalizedName == null || normalizedName.isEmpty) return;
    if (!mounted) return;
    if (index >= _widgets.length || !identical(_widgets[index], widgetConfig)) {
      return;
    }
    setState(() => widgetConfig['name'] = normalizedName);
    _markDirty();
  }

  String _widgetListSubtitle(JsonMap item) {
    if (item['visible'] == false) return 'Hidden in overlay';
    if (_presence.connected) return 'Connected (${_presence.subscribers})';
    return 'OBS source disconnected';
  }

  Widget _widgetListIcon(JsonMap item) {
    final definition = _overlayWidgetCatalog
        .cast<GeneratedOverlayWidget?>()
        .firstWhere(
          (candidate) =>
              candidate?.pluginId == OverlayWidgetPresentation.pluginId(item) &&
              candidate?.id == OverlayWidgetPresentation.widgetId(item),
          orElse: () => null,
        );
    final icon = definition == null
        ? const Icon(Icons.widgets_outlined, size: 18)
        : overlayWidgetIconWidget(definition, size: 18);
    if (item['locked'] != true) return icon;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        const Positioned(
          right: -5,
          bottom: -5,
          child: Icon(Icons.lock, size: 10),
        ),
      ],
    );
  }
}

class _OverlayLayerTitle extends StatefulWidget {
  const _OverlayLayerTitle({
    super.key,
    required this.widgetId,
    required this.name,
    required this.onSelected,
    required this.onRenamed,
  });
  final String widgetId;
  final String name;
  final VoidCallback onSelected;
  final ValueChanged<String> onRenamed;
  @override
  State<_OverlayLayerTitle> createState() => _OverlayLayerTitleState();
}

class _OverlayLayerTitleState extends State<_OverlayLayerTitle> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) _finish();
    });
  }

  void _start() {
    widget.onSelected();
    _controller.value = TextEditingValue(
      text: widget.name,
      selection: TextSelection(baseOffset: 0, extentOffset: widget.name.length),
    );
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing) _focus.requestFocus();
    });
  }

  void _finish({bool cancel = false}) {
    if (!_editing) return;
    final name = _controller.text.trim();
    setState(() => _editing = false);
    if (!cancel && name.isNotEmpty && name != widget.name) {
      widget.onRenamed(name);
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _editing
      ? Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              _finish(cancel: true);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: TextField(
            key: ValueKey('overlay-layer-rename-${widget.widgetId}'),
            controller: _controller,
            focusNode: _focus,
            style: Theme.of(context).textTheme.bodyMedium,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            ),
            onSubmitted: (_) => _finish(),
            onTapOutside: (_) => _finish(),
          ),
        )
      : GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onSelected,
          onDoubleTap: _start,
          child: Text(
            widget.name,
            key: ValueKey('overlay-widget-row-title-${widget.widgetId}'),
            semanticsLabel: widget.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
        );
}

class _OverlayWidgetRenameDialog extends StatefulWidget {
  const _OverlayWidgetRenameDialog({
    required this.widgetId,
    required this.name,
  });

  final String widgetId;
  final String name;

  @override
  State<_OverlayWidgetRenameDialog> createState() =>
      _OverlayWidgetRenameDialogState();
}

class _OverlayWidgetRenameDialogState
    extends State<_OverlayWidgetRenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.name);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Rename ${widget.name}'),
    content: TextField(
      key: ValueKey('overlay-widget-rename-${widget.widgetId}'),
      controller: _controller,
      autofocus: true,
      decoration: const InputDecoration(labelText: 'Name'),
      onSubmitted: (value) => Navigator.of(context).pop(value),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_controller.text),
        child: const Text('Rename'),
      ),
    ],
  );
}

class _OverlayWidgetMenu extends StatefulWidget {
  const _OverlayWidgetMenu({
    required this.catalog,
    required this.height,
    required this.onSelected,
  });

  final List<GeneratedOverlayWidget> catalog;
  final double height;
  final ValueChanged<GeneratedOverlayWidget> onSelected;

  @override
  State<_OverlayWidgetMenu> createState() => _OverlayWidgetMenuState();
}

class _OverlayWidgetMenuState extends State<_OverlayWidgetMenu> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final filtered = widget.catalog
        .where(
          (definition) =>
              query.isEmpty ||
              definition.name.toLowerCase().contains(query) ||
              definition.id.toLowerCase().contains(query) ||
              definition.pluginId.toLowerCase().contains(query),
        )
        .toList(growable: false);
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 300,
        height: widget.height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: TextField(
                key: const ValueKey('overlay-widget-search'),
                controller: _search,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search widgets',
                  isDense: true,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('No widgets found'))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final definition = filtered[index];
                        return InkWell(
                          onTap: () => widget.onSelected(definition),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            child: Row(
                              children: [
                                overlayWidgetIconWidget(definition),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    definition.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
