import 'dart:io';
import '../../services/showrunner_data_service.dart';
import '../../persistence/profile_repository.dart';
import '../../runtime/profile_runtime.dart';
import '../../runtime/expression.dart';
import '../../schema/profile.dart';
import '../navigation/workspace_navigation_controller.dart';

final class ProfileActivationWorkflow {
  const ProfileActivationWorkflow(this.dataService, this.runtime);
  final ShowRunnerDataService dataService;
  final Future<DartProfileRuntime> Function() runtime;
  Future<bool> run(
    String requestedProfileId,
    String activation,
    EvaluationContext context,
  ) async {
    final profileId = requestedProfileId.endsWith('.yaml')
        ? requestedProfileId.substring(0, requestedProfileId.length - 5)
        : requestedProfileId;
    if (!WorkspaceNavigationSnapshot.isSafeResourceId(profileId)) return false;
    final file = File(
      '${dataService.userDirectory.path}/profiles/$profileId.yaml',
    );
    final repository = ProfileRepository(file);
    final profile = await repository.load();
    if (profile == null) return false;
    final runtime = await this.runtime();
    final nextMode = switch (activation) {
      'true' => 'always',
      'false' => 'manual',
      'toggle-active' => runtime.isActive(profileId) ? 'manual' : 'always',
      _ => 'toggle',
    };
    final updated = ShowRunnerProfile(
      name: profile.name,
      activationMode: nextMode,
      triggers: profile.triggers,
      activationCondition: profile.activationCondition,
      activationAutomation: profile.activationAutomation,
      deactivationAutomation: profile.deactivationAutomation,
      extra: profile.extra,
    );
    if (updated.activationMode != profile.activationMode) {
      await repository.save(updated);
    }
    final desired = runtime.shouldBeActive(updated, context: context);
    await runtime.setManagedActive(
      profileId,
      updated,
      active: desired,
      context: context,
    );
    return runtime.isActive(profileId);
  }
}
