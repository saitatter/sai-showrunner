import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/variables/variables_catalog_controller.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/plugins/variables/runtime.dart';
import 'package:showrunner_flutter/schema/resource.dart';

void main() {
  test(
    'value bursts do not reread the catalog; definition changes refresh it',
    () async {
      final root = await Directory.systemTemp.createTemp('variable-catalog-');
      final repository = ResourceRepository(root);
      ResourceData variable(String name) => ResourceData(
        id: 'counter',
        config: {
          'name': name,
          'type': 'number',
          'defaultValue': 0,
          'persistent': false,
        },
      );
      await repository.save(variable('Counter'));
      final runtime = DartVariableRuntime(directory: root);
      await runtime.load();
      var reads = 0;
      final controller = VariablesCatalogController(
        runtime: runtime,
        load: () {
          reads++;
          return repository.list();
        },
      );
      addTearDown(() async {
        await controller.close();
        await runtime.close();
        await root.delete(recursive: true);
      });
      await controller.refresh();
      var notifications = 0;
      controller.addListener(() => notifications++);
      for (var i = 1; i <= 30; i++) {
        await runtime.setValue('counter', i);
      }
      expect(reads, 1);
      expect(notifications, 0);
      await repository.save(variable('Renamed'));
      await runtime.reload();
      await controller.refresh();
      expect(controller.rows.single.name, 'Renamed');
      expect(reads, lessThanOrEqualTo(3));
      expect(() => controller.rows.clear(), throwsUnsupportedError);
    },
  );
  test(
    'overlapping refreshes share ownership and drain one trailing read',
    () async {
      final first = Completer<List<ResourceData>>();
      var reads = 0;
      final controller = VariablesCatalogController(
        load: () {
          reads++;
          return reads == 1 ? first.future : Future.value([]);
        },
      );
      addTearDown(controller.dispose);
      final pending = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(identical(pending, controller.refresh()), isTrue);
      expect(reads, 1);
      first.complete([]);
      await pending;
      expect(reads, 2);
      expect(controller.loading, isFalse);
    },
  );
  test(
    'close drains accepted reads and rejects late view publication',
    () async {
      final result = Completer<List<ResourceData>>();
      final controller = VariablesCatalogController(load: () => result.future);
      var changes = 0;
      controller.addListener(() => changes++);
      final read = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      var closed = false;
      final closing = controller.close().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      result.complete([]);
      await Future.wait([read, closing]);
      expect(changes, 0);
    },
  );
}
