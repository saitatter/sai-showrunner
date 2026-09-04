import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/aitum/manifest.dart';
import 'package:showrunner_flutter/plugins/obs/actions.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';

void main() {
  test('maps Aitum vertical controls to OBS vendor requests', () async {
    final calls = <({String request, dynamic data})>[];
    final registry = DartPluginRegistry()
      ..register(
        createAitumPlugin(
          CallbackObsTransport((request, data) async {
            calls.add((request: request, data: data));
            if (data['requestType'] == 'status') {
              return {
                'responseData': {'backtrack': true},
              };
            }
            return <String, dynamic>{};
          }),
        ),
      );

    await registry.invokeAction('aitum', 'verticalScene', {
      'scene': 'Portrait',
    });
    await registry.invokeAction('aitum', 'verticalStreamStartStop', {
      'streaming': true,
    });
    await registry.invokeAction('aitum', 'verticalRecordingStartStop', {
      'streaming': false,
    });
    await registry.invokeAction('aitum', 'verticalBacktrackStartStop', {
      'streaming': 'toggle',
    });
    await registry.invokeAction('aitum', 'saveBacktrack', {});
    await registry.invokeAction('aitum', 'verticalChapterMarker', {
      'chapterName': 'Boss fight',
    });

    expect(calls.map((call) => call.data['requestType']), [
      'switch_scene',
      'start_streaming',
      'stop_recording',
      'status',
      'stop_backtrack',
      'save_backtrack',
      'add_chapter',
    ]);
    expect(calls.first.data['requestData'], {'scene': 'Portrait'});
    expect(calls.last.data['requestData'], {'chapter_name': 'Boss fight'});
  });
}
