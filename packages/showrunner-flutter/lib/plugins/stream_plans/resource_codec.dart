import '../../schema/resource_codec.dart';
import '../../schema/json.dart';
import '../../graph/domain/automation_document.dart';

final class StreamPlanConfigurationCodec extends ResourceConfigurationCodec {
  const StreamPlanConfigurationCodec();
  @override
  void validate(JsonMap config) {
    super.validate(config);
    void automation(Object? value) {
      final map = ResourceConfigurationCodec.optionalObject(
        value,
        'Stream Plan automation',
      );
      if (map != null) {
        AutomationDocument.fromJson(Map<String, dynamic>.from(map));
      }
    }

    automation(config['activationAutomation']);
    automation(config['deactivationAutomation']);
    for (final segment in ResourceConfigurationCodec.objectList(
      config['segments'],
      'Stream Plan segments',
    )) {
      for (final field in ['id', 'name']) {
        if (segment[field] != null && segment[field] is! String) {
          throw const FormatException(
            'Stream Plan segment IDs and names must be text.',
          );
        }
      }
      ResourceConfigurationCodec.optionalObject(
        segment['components'],
        'Stream Plan components',
      );
      automation(segment['activationAutomation']);
      automation(segment['deactivationAutomation']);
    }
  }
}
