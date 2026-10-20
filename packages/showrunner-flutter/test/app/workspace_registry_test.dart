import 'package:flutter_test/flutter_test.dart';

import 'package:showrunner_flutter/app/workspace_registry.dart';
import 'package:showrunner_flutter/app/workspace_host.dart';

void main() {
  test(
    'each stable descriptor resolves to a feature-owned workspace builder',
    () {
      const registry = WorkspaceRegistry();
      expect(registry.builders.keys.toSet(), WorkspaceIds.all.toSet());
      for (final id in WorkspaceIds.all) {
        expect(registry.resolve(id).descriptor.id, id);
        expect(registry.resolve(id).builder, same(registry.builders[id]));
      }
      expect(
        registry.resolve(WorkspaceIds.overlay('one')).descriptor.id,
        WorkspaceIds.overlay('one'),
      );
      expect(
        registry.resolve(const WorkspaceId('unknown')).descriptor.id,
        WorkspaceIds.logs,
      );
    },
  );
  test('keeps workspace IDs unique and described', () {
    expect(WorkspaceIds.all.toSet(), hasLength(WorkspaceIds.all.length));
    expect(
      workspaceDescriptors.map((descriptor) => descriptor.id).toSet(),
      containsAll(WorkspaceIds.all),
    );
  });

  test('resolves known descriptors and a safe fallback', () {
    expect(workspaceDescriptorFor(WorkspaceIds.settings).title, 'Settings');
    expect(
      workspaceDescriptorFor(const WorkspaceId('workspace.unknown')).id,
      WorkspaceIds.logs,
    );
  });

  test('uses stable per-resource IDs for stream plan documents', () {
    const id = 'show-plan-1';
    final workspace = WorkspaceIds.streamPlan(id);
    expect(WorkspaceIds.isStreamPlan(workspace), isTrue);
    expect(WorkspaceIds.streamPlanResourceId(workspace), id);
  });
}
