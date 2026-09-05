import 'dart:convert';
import 'dart:io';

import 'filesystem/atomic_file.dart';
import 'migrations/legacy_import_service.dart';
import '../schema/profile.dart';

final class ProfileRepository {
  const ProfileRepository(this.file);

  final File file;

  Future<ShowRunnerProfile?> load() async {
    if (!await file.exists()) return null;
    final source = await readStructuredMap(file);
    try {
      return ShowRunnerProfile.fromJson(source);
    } on FormatException {
      final service = const LegacyImportService();
      final normalized = service.normalizeProfileMap(source);
      final profile = ShowRunnerProfile.fromJson(normalized);
      await backupOriginalFile(file);
      await writeAtomicText(
        file,
        const JsonEncoder.withIndent('  ').convert(profile.toJson()),
      );
      return profile;
    }
  }

  Future<void> save(ShowRunnerProfile profile) async {
    await writeAtomicText(
      file,
      const JsonEncoder.withIndent('  ').convert(profile.toJson()),
    );
  }
}
