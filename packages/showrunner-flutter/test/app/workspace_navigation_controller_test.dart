import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/app/navigation/workspace_navigation_controller.dart';
import 'package:showrunner_flutter/app/workspace_registry.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  test('codec omits unknown and unsafe IDs without changing document data', () {
    final snapshot = WorkspaceNavigationSnapshot.fromSettings({
      'openWorkspaceTabs': [
        'workspace.chat',
        'retired',
        'workspace.overlay.../escape',
        'workspace.chat',
        'workspace.overlay.safe',
      ],
      'selectedWorkspace': 'retired',
      'openAutomationTabs': ['a.yaml', '../private.yaml', 'a.yaml', 7],
      'selectedAutomationTab': '../private.yaml',
    });
    expect(snapshot.tabs, [WorkspaceIds.chat, WorkspaceIds.overlay('safe')]);
    expect(snapshot.automations, ['a.yaml']);
    expect(snapshot.selected, isNull);
    expect(snapshot.selectedAutomation, isNull);
    expect(() => snapshot.tabs.add(WorkspaceIds.home), throwsUnsupportedError);
  });

  test('early navigation applies after restoration in request order', () async {
    final root = await Directory.systemTemp.createTemp('navigation-order-');
    final data = ShowRunnerDataService(root);
    await data.savePluginSettings('showrunner-flutter', {
      'openWorkspaceTabs': ['workspace.home', 'workspace.graph'],
      'selectedWorkspace': 'workspace.graph',
    });
    final controller = WorkspaceNavigationController(
      dataService: data,
      automationSettings: () => {},
    );
    final entered = Completer<void>(), release = Completer<void>();
    final restore = controller.restore(
      restoreDocuments: (_) async {
        entered.complete();
        await release.future;
      },
      isAvailable: (_) => true,
    );
    await entered.future;
    controller.openWorkspace(WorkspaceIds.chat);
    controller.openResource('Overlay', 'selected');
    release.complete();
    await restore;
    expect(controller.documents.openWorkspaces, [
      WorkspaceIds.home,
      WorkspaceIds.graph,
      WorkspaceIds.chat,
      WorkspaceIds.resources,
    ]);
    expect(controller.snapshot.selected, WorkspaceIds.resources);
    expect(controller.snapshot.resourceId, 'selected');
    await controller.close();
    await root.delete(recursive: true);
  });

  test(
    'coalesced navigation writes retain other settings owners and drain on close',
    () async {
      final root = await Directory.systemTemp.createTemp('navigation-writes-');
      final data = ShowRunnerDataService(root);
      final controller = WorkspaceNavigationController(
        dataService: data,
        automationSettings: () => {
          'openAutomationTabs': ['one.yaml'],
        },
        writeDelay: const Duration(days: 1),
      );
      await controller.restore(
        restoreDocuments: (_) async {},
        isAvailable: (_) => true,
      );
      controller.openWorkspace(WorkspaceIds.graph);
      final first = controller.persist();
      controller.openWorkspace(WorkspaceIds.chat);
      final second = controller.persist();
      await data.updatePluginSetting(
        'showrunner-flutter',
        'projectSidebarWidth',
        350,
      );
      await controller.close();
      await Future.wait([first, second]);
      final saved = await data.loadPluginSettings('showrunner-flutter');
      expect(saved['selectedWorkspace'], 'workspace.chat');
      expect(saved['openAutomationTabs'], ['one.yaml']);
      expect(saved['projectSidebarWidth'], 350);
      controller.openWorkspace(WorkspaceIds.home);
      expect(controller.documents.selectedWorkspace, WorkspaceIds.chat);
      await controller.close();
      await root.delete(recursive: true);
    },
  );

  test('a failed write does not poison later navigation writes', () async {
    final root = await Directory.systemTemp.createTemp('navigation-retry-');
    final data = ShowRunnerDataService(root);
    final controller = WorkspaceNavigationController(
      dataService: data,
      automationSettings: () => {},
    );
    await controller.restore(
      restoreDocuments: (_) async {},
      isAvailable: (_) => true,
    );
    final blocker = await Directory(
      '${root.path}/settings/showrunner-flutter.yaml',
    ).create(recursive: true);
    final failed = controller.persist();
    final expectation = expectLater(
      failed,
      throwsA(isA<FileSystemException>()),
    );
    await expectLater(controller.flush(), throwsA(isA<FileSystemException>()));
    await expectation;
    await blocker.delete();
    controller.openWorkspace(WorkspaceIds.chat);
    final recovered = controller.persist();
    await controller.flush();
    await recovered;
    expect(
      (await data.loadPluginSettings(
        'showrunner-flutter',
      ))['selectedWorkspace'],
      'workspace.chat',
    );
    await controller.close();
    await root.delete(recursive: true);
  });
}
