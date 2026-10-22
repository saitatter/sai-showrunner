import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sai_nodes/sai_nodes.dart' show NodeEditor;
import 'package:showrunner_flutter/plugins/overlays/shader_graph/shader_graph_editor.dart';
import 'shader_editor_workflow_test.dart' show open, click, controller;

void main() {
  testWidgets(
    'palette search does not rebuild the shader workspace and survives hiding',
    (tester) async {
      var builds = 0;
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, once) {
        previous?.call(element, once);
        if (element.widget is ShaderGraphEditorDialog) builds++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);
      await open(tester);
      final baseline = builds;
      await tester.enterText(
        find.widgetWithText(TextField, 'Search shader nodes'),
        'Float',
      );
      await tester.pump();
      expect(builds, baseline);
      await click(tester, 'Toggle node palette');
      await click(tester, 'Toggle node palette');
      expect(
        tester
                .widget<TextField>(
                  find.widgetWithText(TextField, 'Search shader nodes'),
                )
                .controller
                ?.text ??
            tester
                .widget<EditableText>(
                  find.descendant(
                    of: find.widgetWithText(TextField, 'Search shader nodes'),
                    matching: find.byType(EditableText),
                  ),
                )
                .controller
                .text,
        'Float',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'a picker opened before reset cannot insert into the replacement graph',
    (tester) async {
      await open(tester);
      final before = controller(tester).activeSpace!.nodes.length;
      await click(tester, 'Add shader node');
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton && widget.tooltip == 'Reset graph',
            ),
          )
          .onPressed!();
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'Search shader nodes').last,
        'Float Parameter',
      );
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(ListTile, 'Float Parameter'),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller(tester).activeSpace!.nodes.length, before);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Ctrl+F focuses a shader node without changing authoring or compile output',
    (tester) async {
      await open(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Compile & apply'));
      await tester.pumpAndSettle();
      expect(find.text('Shader compiled successfully.'), findsOneWidget);
      final graph = controller(tester);
      final revision = graph.semanticRevision;
      final id = graph.activeSpace!.nodes.keys.first;
      await tester.tapAt(tester.getCenter(find.byType(NodeEditor)));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Search graph nodes'),
        id,
      );
      await tester.pump();
      await tester.tap(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(ListTile),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(graph.selection.nodes, {id});
      expect(graph.semanticRevision, revision);
      expect(find.text('Shader compiled successfully.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final size in const [
    Size(1024, 640),
    Size(1280, 720),
    Size(1440, 900),
    Size(1920, 1080),
  ]) {
    for (final dpr in [1.0, 1.5]) {
      testWidgets(
        'shader controls fit $size DPR $dpr with scaled text and compilation',
        (tester) async {
          tester.view.devicePixelRatio = dpr;
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.binding.setSurfaceSize(size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  devicePixelRatio: dpr,
                  textScaler: TextScaler.linear(1.5),
                ),
                child: const Scaffold(
                  body: ShaderGraphEditorDialog(config: {}),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.widgetWithText(FilledButton, 'Compile & apply'),
          );
          await tester.pumpAndSettle();
          expect(find.text('Shader compiled successfully.'), findsOneWidget);
          expect(tester.takeException(), isNull);
          expect(
            tester.getSize(find.byType(NodeEditor)).height,
            greaterThan(80),
          );
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
