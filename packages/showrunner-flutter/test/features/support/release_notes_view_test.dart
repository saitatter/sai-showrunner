import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/support/release_notes_view.dart';

void main() {
  testWidgets('renders common release Markdown and opens safe links', (
    tester,
  ) async {
    Uri? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReleaseNotesView(
              source: '''
# What changed

**Bold** and *italic* text.

[details](https://example.test/release)

- First item
- Second item with `code`

> A note for users

```dart
void main() {}
```
''',
              onOpenLink: (uri) async => opened = uri,
            ),
          ),
        ),
      ),
    );

    expect(find.text('What changed', findRichText: true), findsOneWidget);
    expect(find.text('First item', findRichText: true), findsOneWidget);
    expect(
      find.text('Second item with code', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('A note for users', findRichText: true), findsOneWidget);
    expect(find.text('void main() {}'), findsOneWidget);

    final link = find.text('details', findRichText: true);
    await tester.tapAt(tester.getTopLeft(link) + const Offset(8, 8));
    await tester.pump();
    expect(opened, Uri.parse('https://example.test/release'));
  });

  testWidgets('renders invalid-scheme Markdown links as inert text', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReleaseNotesView(
            source: '[unsafe](javascript:alert)',
            onOpenLink: (_) async => opened = true,
          ),
        ),
      ),
    );

    expect(find.text('unsafe', findRichText: true), findsOneWidget);
    final unsafeLink = find.text('unsafe', findRichText: true);
    await tester.tapAt(tester.getTopLeft(unsafeLink) + const Offset(8, 8));
    await tester.pump();
    expect(opened, isFalse);
  });
}
