import 'overlay_preview_settings_dialog.dart';
import 'overlay_obs_controller.dart';
import 'overlay_obs_source_control.dart';
import 'overlay_presence_controller.dart';
import 'overlay_browser_source_panel.dart';
import 'overlay_editor_layout.dart';
import 'overlay_editor_controller.dart';
import 'overlay_editor_toolbar.dart';
import 'overlay_widget_palette.dart';
import 'overlay_widget_rename_dialog.dart';
import 'overlay_layers_panel.dart';
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
import 'package:showrunner_flutter/features/resources/overlay/overlay_snapping.dart';
import 'package:showrunner_flutter/plugins/overlays/generated_widget_catalog.dart';
import 'package:showrunner_flutter/plugins/overlays/overlay_presence.dart';

import 'package:showrunner_flutter/plugins/overlays/ui/editor/overlay_canvas.dart';
import 'package:showrunner_flutter/plugins/overlays/ui/editor/overlay_widget_inspector.dart';

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
  late OverlayEditorController _editor;
  final _canvasFocus = FocusNode(debugLabel: 'Overlay canvas');
  List<JsonMap> get _widgets => _editor.widgets;
  int? get _selectedWidgetIndex => _editor.selectedIndex;
  set _selectedWidgetIndex(int? value) {
    _canvasFocus.requestFocus();
    _editor.selectIndex(value);
  }

  late OverlayPreviewSettings _previewDraft;
  bool get _previewEnabled => _editor.resource.config['preview'] is Map;
  List<GeneratedOverlayWidget> _overlayWidgetCatalog =
      GeneratedOverlayWidgetCatalog.widgets;
  var _layoutKey = GlobalKey<OverlayEditorLayoutState>();
  bool get _dirty => _editor.dirty;
  bool get _saving => _editor.saving;
  int _reportedRevision = 0;
  bool _reportedDirty = false;
  late final OverlayPresenceController _presenceController;
  late final OverlayObsController _obsController;
  final _widgetMenuLink = LayerLink();
  final _widgetMenuAnchorKey = GlobalKey();
  OverlayEntry? _widgetMenuEntry;
  Object? _canvasTransformItem;
  JsonMap _canvasTransformPosition = const {};
  JsonMap _canvasTransformSize = const {};
  Offset _canvasTransformDelta = Offset.zero;
  bool _snapEnabled = true;
  List<double> _verticalGuides = const [];
  List<double> _horizontalGuides = const [];

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _width = TextEditingController();
    _height = TextEditingController();
    _installDocument();
    _presenceController = OverlayPresenceController(
      widget.resource.id,
      widget.presenceReaderFuture,
    );
    _obsController = OverlayObsController(
      overlayId: widget.resource.id,
      width: _canvasDimension(_width, 1920),
      height: _canvasDimension(_height, 1080),
      port: () => _presenceController.port,
      service: widget.obsSourceService,
    );
    GeneratedOverlayWidgetCatalog.load().then((widgets) {
      if (!mounted) return;
      setState(() => _overlayWidgetCatalog = widgets);
    });
  }

  void _installDocument() {
    _editor = OverlayEditorController(widget.resource)
      ..addListener(_editorChanged);
    _reportedRevision = 0;
    _reportedDirty = false;
    _loadInputFields(widget.resource);
    _scheduleSnapshot();
  }

  void _loadInputFields(ResourceData resource) {
    final overlay = OverlayResource.fromResource(resource);
    _name.text = overlay.name;
    _width.text = '${overlay.width}';
    _height.text = '${overlay.height}';
    _previewDraft = OverlayPreviewSettings.fromConfig(
      resource.config['preview'],
    );
  }

  void _editorChanged() {
    if (!mounted) return;
    setState(() {});
    final changed =
        _reportedRevision != _editor.revision || _reportedDirty != _dirty;
    if (_reportedDirty != _dirty) widget.onDirtyChanged?.call(_dirty);
    _reportedRevision = _editor.revision;
    _reportedDirty = _dirty;
    if (changed) _scheduleSnapshot();
  }

  @override
  void didUpdateWidget(covariant OverlayEditorPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedIdentity = oldWidget.resource.id != widget.resource.id;
    final changedPresence =
        oldWidget.presenceReaderFuture != widget.presenceReaderFuture;
    if (changedIdentity) {
      _closeWidgetMenu();
      _layoutKey = GlobalKey<OverlayEditorLayoutState>();
      _editor.dispose();
      _installDocument();
      _canvasTransformItem = null;
      _verticalGuides = const [];
      _horizontalGuides = const [];
    }
    if (changedIdentity || changedPresence) {
      _presenceController.configure(
        widget.resource.id,
        widget.presenceReaderFuture,
      );
    }
    if (changedIdentity ||
        changedPresence ||
        oldWidget.obsSourceService != widget.obsSourceService) {
      _obsController.configure(
        overlayId: widget.resource.id,
        width: _canvasDimension(_width, 1920),
        height: _canvasDimension(_height, 1080),
        port: () => _presenceController.port,
        service: widget.obsSourceService,
      );
    }
  }

  @override
  void dispose() {
    _closeWidgetMenu();
    _presenceController.dispose();
    _obsController.dispose();
    _editor.dispose();
    _canvasFocus.dispose();
    _name.dispose();
    _width.dispose();
    _height.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canvasWidth = _canvasDimension(_width, 1920);
    final canvasHeight = _canvasDimension(_height, 1080);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): _redo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redo,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            unawaited(_saveOverlay()),
        const SingleActivator(LogicalKeyboardKey.keyI, control: true): () =>
            _layoutKey.currentState?.toggleInspector(),
      },
      child: Focus(
        focusNode: _canvasFocus,
        autofocus: true,
        child: Material(
          key: const ValueKey('overlay-editor-root'),
          color: ShowRunnerColors.surfaceB,
          child: OverlayEditorLayout(
            key: _layoutKey,
            toolbar: ListenableBuilder(
              listenable: _obsController,
              builder: (context, child) {
                final obs = _obsController.view;
                return OverlayEditorToolbar(
                  nameController: _name,
                  widthController: _width,
                  heightController: _height,
                  snapEnabled: _snapEnabled,
                  onSnapToggle: () => setState(() {
                    _snapEnabled = !_snapEnabled;
                    _verticalGuides = const [];
                    _horizontalGuides = const [];
                  }),
                  onNameChanged: _markDirty,
                  onSizeChanged: () {
                    _markDirty();
                    setState(() {});
                    _scheduleObsSourceRefresh();
                  },
                  onSizePreset: _setSizePreset,
                  onPreviewSettings: () => _showPreviewSettings(context),
                  obsConnections: obs.connections,
                  obsConnectionsLoading: obs.connectionsLoading,
                  selectedObsConnectionId: obs.selectedId,
                  onSelectObsConnection: _obsController.select,
                  obsSourceControl: !obs.available
                      ? null
                      : OverlayObsSourceControl(
                          view: obs,
                          onOpen: () => unawaited(_openObs()),
                          onCheck: () => unawaited(_obsController.refresh()),
                          onCreate: () => unawaited(_createObsBrowserSource()),
                          onFix: () => unawaited(_fixObsBrowserSource()),
                        ),
                );
              },
            ),
            canvas: OverlayCanvas(
              width: canvasWidth,
              height: canvasHeight,
              widgets: _widgets,
              selectedIndex: _selectedWidgetIndex,
              catalog: _overlayWidgetCatalog,
              onTransformStart: _beginCanvasTransform,
              onTransformEnd: _endCanvasTransform,
              verticalGuides: _verticalGuides,
              horizontalGuides: _horizontalGuides,
              onSelect: (index) {
                _canvasFocus.requestFocus();
                setState(() => _selectedWidgetIndex = index);
              },
              onDeselect: () => setState(() {
                _canvasFocus.requestFocus();
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
            inspector: _overlayInspector(context),
            layers: _overlayWidgetList(context),
            status: _previewEnabled
                ? 'Preview enabled'
                : 'No live preview configured',
            saving: _saving,
            onSave: () => unawaited(_saveOverlay()),
            onReturnToCanvas: _canvasFocus.requestFocus,
          ),
        ),
      ),
    );
  }

  void _undo() {
    _editor.undo();
    _loadInputFields(_editor.resource);
    _scheduleObsSourceRefresh();
  }

  void _redo() {
    _editor.redo();
    _loadInputFields(_editor.resource);
    _scheduleObsSourceRefresh();
  }

  OverlayEditorController? _snapshotOwner;
  void _markDirty() => _editor.replace(_snapshot());

  void _scheduleSnapshot() {
    if (identical(_snapshotOwner, _editor) ||
        widget.onDocumentChanged == null) {
      return;
    }
    final owner = _editor;
    _snapshotOwner = owner;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (identical(_snapshotOwner, owner)) _snapshotOwner = null;
      if (mounted && identical(owner, _editor)) {
        widget.onDocumentChanged?.call(_snapshot(), _dirty);
      }
    });
  }

  void _scheduleObsSourceRefresh() => _obsController.setDimensions(
    _canvasDimension(_width, 1920),
    _canvasDimension(_height, 1080),
  );

  Future<void> _openObs() async {
    final token = _obsController.contextToken;
    final opened = await _obsController.open();
    if (!mounted || !_obsController.isCurrent(token)) return;
    showShowRunnerFeedback(
      context,
      opened == true
          ? 'Opening OBS Studio.'
          : _obsController.view.error ??
                'Could not find OBS. Check the OBS install path in its connection settings.',
      severity: opened == true
          ? ShowRunnerFeedbackSeverity.success
          : ShowRunnerFeedbackSeverity.warning,
    );
  }

  Future<void> _createObsBrowserSource() async {
    final token = _obsController.contextToken;
    final sourceName = await showShowRunnerNameDialog(
      context,
      title: 'Create Browser Source',
      initialName:
          '${_name.text.trim().isEmpty ? 'Overlay' : _name.text.trim()} Browser Source',
    );
    if (!mounted || sourceName == null || !_obsController.isCurrent(token)) {
      return;
    }
    final created = await _obsController.create(
      sourceName,
      expectedContext: token,
    );
    if (!mounted || !_obsController.isCurrent(token) || created) return;
    showShowRunnerFeedback(
      context,
      _obsController.view.error ?? 'Could not create the OBS Browser Source.',
      severity: ShowRunnerFeedbackSeverity.error,
    );
  }

  Future<void> _fixObsBrowserSource() async {
    final token = _obsController.contextToken;
    final fixed = await _obsController.fix(expectedContext: token);
    if (!mounted || !_obsController.isCurrent(token) || fixed) return;
    showShowRunnerFeedback(
      context,
      _obsController.view.error ?? 'Could not update the OBS Browser Source.',
      severity: ShowRunnerFeedbackSeverity.error,
    );
  }

  Widget _overlayInspector(BuildContext context) {
    final index = _selectedWidgetIndex;
    if (index == null || index < 0 || index >= _widgets.length) {
      return const Center(child: Text('Select a widget to edit it.'));
    }
    final selected = _widgets[index];
    final owner = _editor;
    final layerKey = owner.keyAt(index);
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
            if (!mounted || !identical(owner, _editor)) return;
            owner.updateWidget(layerKey, {key: value});
            _markDirty();
          },
          catalog: _overlayWidgetCatalog,
          templateSuggestions: widget.templateSuggestions,
        ),
      ),
    );
  }

  Widget _overlayWidgetList(BuildContext context) {
    final owner = _editor;
    void at(Object key, void Function(int) action) {
      if (!mounted || !identical(owner, _editor)) return;
      final index = owner.indexOfKey(key);
      if (index >= 0) action(index);
    }

    final showBrowserSourceCard = MediaQuery.sizeOf(context).height >= 900;
    return OverlayLayersPanel(
      editor: owner,
      catalog: _overlayWidgetCatalog,
      presence: _presenceController,
      header: Row(
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
              icon: ValueListenableBuilder<OverlayPresenceView>(
                valueListenable: _presenceController,
                builder: (context, view, _) => Icon(
                  view.presence.connected
                      ? Icons.wifi_tethering
                      : Icons.wifi_tethering_off,
                ),
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
      footer: showBrowserSourceCard ? _overlayBrowserSourceCard(context) : null,
      onSelected: (key) =>
          at(key, (index) => setState(() => _selectedWidgetIndex = index)),
      onReorder: (from, to) {
        if (mounted && identical(owner, _editor)) _reorderWidgets(from, to);
      },
      onAction: (key, action) => at(key, (index) {
        switch (action) {
          case 'rename':
            unawaited(_renameWidget(index));
          case 'up':
            _moveWidget(index, -1);
          case 'down':
            _moveWidget(index, 1);
          case 'visible':
            _toggleWidgetFlag(index, 'visible');
          case 'locked':
            _toggleWidgetFlag(index, 'locked');
          case 'delete':
            _deleteWidget(index);
        }
      }),
    );
  }

  Widget _overlayBrowserSourceCard(BuildContext context) =>
      OverlayBrowserSourcePanel(presence: _presenceController);

  Future<void> _showPreviewSettings(BuildContext context) async {
    final owner = _editor;
    await showDialog<void>(
      context: context,
      builder: (context) => OverlayPreviewSettingsDialog(
        initial: _previewDraft,
        onChanged: (settings) {
          if (!mounted || !identical(owner, _editor)) return;
          _previewDraft = settings;
          owner.replace(
            owner.compose(
              name: _name.text.trim(),
              width: _canvasDimension(_width, 1920),
              height: _canvasDimension(_height, 1080),
              preview: settings.toConfig(),
            ),
          );
        },
      ),
    );
  }

  ResourceData _snapshot() => _editor.compose(
    name: _name.text.trim(),
    width: _canvasDimension(_width, 1920),
    height: _canvasDimension(_height, 1080),
    preview: _editor.resource.config['preview'] is Map
        ? Map<String, dynamic>.from(_editor.resource.config['preview'] as Map)
        : null,
  );

  Future<void> _saveOverlay() async {
    if (_saving) return;
    final owner = _editor;
    _markDirty();
    try {
      await owner.save(widget.onSave);
    } on Object {
      if (!mounted || !identical(owner, _editor)) return;
      showShowRunnerFeedback(
        context,
        'Could not save overlay: your draft is retained. Check storage access and reload if another editor changed it.',
        severity: ShowRunnerFeedbackSeverity.error,
      );
    }
  }

  int _canvasDimension(TextEditingController controller, int fallback) {
    final value = int.tryParse(controller.text);
    return value != null && value > 0 ? value : fallback;
  }

  void _beginCanvasTransform(int index) {
    if (index < 0 || index >= _widgets.length) return;
    final item = _widgets[index];
    _editor.beginTransaction();
    _canvasTransformItem = _editor.keyAt(index);
    _canvasTransformPosition = item['position'] is Map
        ? Map<String, dynamic>.from(item['position'] as Map)
        : {};
    _canvasTransformSize = item['size'] is Map
        ? Map<String, dynamic>.from(item['size'] as Map)
        : {};
    _canvasTransformDelta = Offset.zero;
  }

  void _endCanvasTransform() {
    _editor.endTransaction();
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
    if (_canvasTransformItem != _editor.keyAt(index)) {
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
      _editor.updateWidget(_editor.keyAt(index), {
        'position': {'x': snapped.left.round(), 'y': snapped.top.round()},
      });
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
      _editor.updateWidget(_editor.keyAt(index), {
        'position': {'x': snapped.left.round(), 'y': snapped.top.round()},
      });
      _editor.updateWidget(_editor.keyAt(index), {
        'size': {
          'width': snapped.width.round(),
          'height': snapped.height.round(),
        },
      });
    });
    _markDirty();
  }

  void _deleteWidget(int index) {
    if (index < 0 || index >= _widgets.length) return;
    setState(() => _editor.deleteWidget(index));
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
            child: OverlayWidgetPalette(
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

  void _setSizePreset(int width, int height) {
    setState(() {
      _width.text = '$width';
      _height.text = '$height';
    });
    _markDirty();
    _scheduleObsSourceRefresh();
  }

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
      _editor.addWidget(widgetConfig);
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
    setState(() => _editor.reorder(oldIndex, newIndex));
    _markDirty();
  }

  void _toggleWidgetFlag(int index, String key) {
    if (index < 0 || index >= _widgets.length) return;
    setState(() {
      _editor.updateWidget(_editor.keyAt(index), {
        key: _widgets[index][key] != true,
      });
    });
    _markDirty();
  }

  Future<void> _renameWidget(int index) async {
    if (index < 0 || index >= _widgets.length) return;
    final widgetConfig = _widgets[index];
    final layerKey = _editor.keyAt(index);
    final owner = _editor;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => OverlayWidgetRenameDialog(
        widgetId: widgetConfig['id']?.toString() ?? '$index',
        name: widgetConfig['name']?.toString() ?? '',
      ),
    );
    final normalizedName = name?.trim();
    if (normalizedName == null || normalizedName.isEmpty) return;
    if (!mounted) return;
    if (!identical(owner, _editor)) return;
    setState(() => _editor.updateWidget(layerKey, {'name': normalizedName}));
    _markDirty();
  }
}
