import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/app/execution/profile_activation_workflow.dart';
import 'package:showrunner_flutter/graph/domain/automation_document.dart';
import 'package:showrunner_flutter/persistence/filesystem/file_transaction.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/runtime/profile_runtime.dart';
import 'package:showrunner_flutter/schema/profile.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  test(
    'profile activation rejects a concurrent author edit before runtime dispatch',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'profile-activation-cas-',
      );
      addTearDown(() => root.delete(recursive: true));
      final data = ShowRunnerDataService(root);
      final repository = data.storage.profile('one.yaml');
      ShowRunnerProfile profile(String name) => ShowRunnerProfile(
        name: name,
        activationMode: 'manual',
        triggers: [],
        activationCondition: {},
        activationAutomation: AutomationDocument.empty(),
        deactivationAutomation: AutomationDocument.empty(),
      );
      await repository.save(profile('Original'));
      final registry = DartPluginRegistry();
      final runtime = DartProfileRuntime(registry: registry);
      addTearDown(registry.close);
      addTearDown(runtime.dispose);
      final entered = Completer<void>();
      final release = Completer<void>();
      final workflow = ProfileActivationWorkflow(data, () async {
        entered.complete();
        await release.future;
        return runtime;
      });
      final activation = workflow.run('one', 'true', EvaluationContext());
      final failure = expectLater(
        activation,
        throwsA(isA<PersistenceConflictException>()),
      );
      await entered.future;
      await repository.save(profile('Editor update'));
      release.complete();
      await failure;
      expect((await repository.load())!.name, 'Editor update');
      expect((await repository.load())!.activationMode, 'manual');
      expect(runtime.isActive('one'), isFalse);
    },
  );
}
