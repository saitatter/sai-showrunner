import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'visual/app_surface_test.dart' as app_surface;
import 'visual/workspace_catalog_test.dart' as workspace_catalog;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('visual/app_surface', app_surface.main);
  group('visual/workspace_catalog', workspace_catalog.main);
}
