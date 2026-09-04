import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/resources/resource_editor_registry.dart';
import 'package:showrunner_flutter/schema/resource.dart';

void main() {
  testWidgets('edits a system TTS voice provider configuration', (tester) async {
    final definition = createDefaultResourceEditorRegistry().find('TTSVoice')!;
    ResourceData? saved;
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final editor = definition.builder(
      tester.element(find.byType(Scaffold)),
      const ResourceData(
        id: 'voice-1',
        config: {
          'name': 'Narrator',
          'voiceProvider': 'system.en-US',
          'providerConfig': {'pitch': 2, 'rate': -1},
        },
      ),
      (resource) async => saved = resource,
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));

    expect(find.text('System voice: system.en-US'), findsOneWidget);
    expect(find.text('Pitch (-10 to 10)'), findsOneWidget);
    expect(find.text('Rate (-10 to 10)'), findsOneWidget);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), '4');
    await tester.enterText(fields.at(2), '-3');
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(saved?.config['voiceProvider'], 'system.en-US');
    expect(saved?.config['providerConfig'], {'pitch': 4, 'rate': -3});
  });
}