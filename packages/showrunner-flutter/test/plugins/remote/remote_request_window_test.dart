import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/remote/remote_request_window.dart';

void main() {
  test(
    'limits actual in-flight requests and releases capacity after completion',
    () {
      final window = RemoteRequestWindow();
      for (var index = 0; index < 16; index++) {
        window.enter('$index');
      }
      expect(() => window.enter('overflow'), throwsStateError);
      window.leave();
      window.enter('replacement');
      expect(() => window.enter('overflow'), throwsStateError);
    },
  );
  test('rejects recent IDs after completion and bounds retained history', () {
    final window = RemoteRequestWindow();
    window.enter('first');
    window.leave();
    expect(() => window.enter('first'), throwsStateError);
    for (var index = 0; index < 256; index++) {
      window.enter('$index');
      window.leave();
    }
    window.enter('first');
    window.leave();
    expect(() => window.enter('255'), throwsStateError);
  });
}
