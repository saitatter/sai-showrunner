import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/viewer_data_repository.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/variables/manifest.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/schema/viewer_data.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';

void main() {
  late InMemoryViewerDataRepository repository;
  late DartPluginRegistry registry;

  setUp(() {
    repository = InMemoryViewerDataRepository(
      definitions: [
        const ViewerVariableDefinition(
          name: 'points',
          type: 'Number',
          defaultValue: 10,
        ),
        const ViewerVariableDefinition(name: 'title', type: 'String'),
      ],
    );
    registry = DartPluginRegistry()
      ..register(createVariablesPlugin(viewerDataRepository: repository));
  });

  test(
    'invokes legacy viewer actions against the injected repository',
    () async {
      final setResult = await registry.invokeAction(
        'variables',
        'setViewerVar',
        {
          'viewer': {'id': '42', 'displayName': 'Ada'},
          'variable': 'title',
          'value': 'Champion',
        },
      );
      expect(setResult, {
        'provider': 'twitch',
        'viewer': '42',
        'variable': 'title',
        'value': 'Champion',
      });

      final offsetResult = await registry.invokeAction(
        'variables',
        'offsetViewerVar',
        {'viewer': '42', 'variable': 'points', 'offset': 2},
      );
      expect(offsetResult, {
        'provider': 'twitch',
        'viewer': '42',
        'variable': 'points',
        'value': 12,
      });
      expect(
        (await repository.loadViewer(
          'twitch',
          const ViewerIdentity(id: '42', displayName: 'Ada'),
        )).values,
        {'points': 12, 'title': 'Champion'},
      );
    },
  );

  test('keeps global variable actions in evaluation context state', () async {
    final context = EvaluationContext(contextState: <String, dynamic>{});
    await registry.invokeAction('variables', 'setVariable', {
      'variable': 'globalCounter',
      'value': 3,
    }, context: context);

    expect(
      await registry.invokeAction('variables', 'getVariable', {
        'variable': 'globalCounter',
      }, context: context),
      {'variable': 'globalCounter', 'value': 3},
    );
    expect(
      (await repository.loadViewer(
        'twitch',
        const ViewerIdentity(id: '42', displayName: 'Ada'),
      )).persisted,
      isFalse,
    );
  });

  test('publishes viewer changes to the in-process event hub', () async {
    final eventHub = DartPluginEventHub();
    final event = eventHub.stream('viewerDataChanged').first;
    final eventRegistry = DartPluginRegistry()
      ..register(
        createVariablesPlugin(
          viewerDataRepository: repository,
          eventHub: eventHub,
        ),
      );

    await eventRegistry.invokeAction('variables', 'setViewerVar', {
      'viewer': {'id': '42', 'displayName': 'Ada'},
      'variable': 'title',
      'value': 'Champion',
    });

    expect(await event, {
      'provider': 'twitch',
      'id': '42',
      'displayName': 'Ada',
      'variable': 'title',
      'value': 'Champion',
      'values': {'points': 10, 'title': 'Champion'},
    });
    await eventHub.dispose();
  });

  test(
    'rejects viewer actions with invalid type or missing identity',
    () async {
      expect(
        () => registry.invokeAction('variables', 'offsetViewerVar', {
          'viewer': '42',
          'variable': 'title',
          'offset': 1,
        }),
        throwsA(isA<StateError>()),
      );
      expect(
        () => registry.invokeAction('variables', 'setViewerVar', {
          'viewer': {'displayName': 'Ada'},
          'variable': 'title',
          'value': 'Champion',
        }),
        throwsA(isA<FormatException>()),
      );
    },
  );
}
