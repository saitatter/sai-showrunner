import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/app/project_panel.dart';
import 'package:showrunner_flutter/services/project_catalog_service.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';
import 'package:showrunner_flutter/schema/identifiers.dart';
import 'package:showrunner_flutter/schema/resource.dart';

void main() {
  late Directory root;
  late ProjectPanelController controller;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('showrunner-catalog-owner-');
    controller = ProjectPanelController(
      catalogService: ShowRunnerProjectCatalogService(root),
      catalogRevision: 0,
    );
    await controller.catalogFuture;
  });
  tearDown(() async {
    await controller.close();
    controller.dispose();
    await root.delete(recursive: true);
  });

  test(
    'equivalent service objects retain the cached catalog until explicit invalidation',
    () async {
      final original = controller.catalogFuture;
      controller.updateCatalog(
        service: ShowRunnerProjectCatalogService(root),
        revision: 0,
      );
      expect(controller.catalogFuture, same(original));
      controller.toggle('overlays');
      expect(controller.catalogFuture, same(original));
      controller.updateCatalog(
        service: ShowRunnerProjectCatalogService(root),
        revision: 1,
      );
      expect(controller.catalogFuture, isNot(same(original)));
      await controller.catalogFuture;
    },
  );

  test(
    'watcher ignores settings and lock metadata but reloads accepted resource writes',
    () async {
      final original = controller.catalogFuture;
      final storage = ShowRunnerDataService(root);
      await storage.updatePluginSetting(
        'showrunner-flutter',
        'test-preference',
        true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(controller.catalogFuture, same(original));
      final changed = Completer<void>();
      controller.addListener(() {
        if (!identical(controller.catalogFuture, original) &&
            !changed.isCompleted) {
          changed.complete();
        }
      });
      await storage.storage
          .resource(const ResourceTypeId('Overlay'))
          .save(const ResourceData(id: 'scene', config: {'name': 'Scene'}));
      await changed.future.timeout(const Duration(seconds: 5));
      final catalog = await controller.catalogFuture!;
      expect(catalog.resources['Overlay']!.single.resource.name, 'Scene');
      final accepted = controller.catalogFuture;
      await controller.close();
      await storage.storage
          .resource(const ResourceTypeId('Overlay'))
          .save(
            const ResourceData(id: 'scene', config: {'name': 'After close'}),
          );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(controller.catalogFuture, same(accepted));
    },
  );

  test(
    'changing roots replaces the owned watcher and isolates later writes',
    () async {
      final other = await Directory('${root.path}/other').create();
      controller.updateCatalog(
        service: ShowRunnerProjectCatalogService(other),
        revision: 0,
      );
      await controller.catalogFuture;
      await controller.close();
      final last = controller.catalogFuture;
      controller.updateCatalog(
        service: ShowRunnerProjectCatalogService(root),
        revision: 2,
      );
      expect(controller.catalogFuture, same(last));
    },
  );
}
