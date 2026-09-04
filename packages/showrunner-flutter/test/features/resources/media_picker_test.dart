import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/resources/media_picker.dart';

void main() {
  testWidgets('filters media files by type and query', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaPicker(
            rootDirectory: Directory('unused'),
            mediaFiles: [
              File(r'C:\media\logo.png'),
              File(r'C:\media\track.mp3'),
              File(r'C:\media\clip.mp4'),
            ],
            allowImages: true,
            allowVideo: true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('logo.png'), findsOneWidget);
    expect(find.text('clip.mp4'), findsOneWidget);
    expect(find.text('track.mp3'), findsNothing);

    await tester.enterText(find.byType(TextField), 'clip');
    await tester.pump();
    expect(find.text('clip.mp4'), findsOneWidget);
    expect(find.text('logo.png'), findsNothing);
  });
}
