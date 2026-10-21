import '../../schema/resource_codec.dart';
import '../../schema/json.dart';

final class DashboardConfigurationCodec extends ResourceConfigurationCodec {
  const DashboardConfigurationCodec();
  @override
  void validate(JsonMap config) {
    super.validate(config);
    for (final page in ResourceConfigurationCodec.objectList(
      config['pages'],
      'Dashboard pages',
    )) {
      for (final section in ResourceConfigurationCodec.objectList(
        page['sections'],
        'Dashboard sections',
      )) {
        for (final widget in ResourceConfigurationCodec.objectList(
          section['widgets'],
          'Dashboard widgets',
        )) {
          ResourceConfigurationCodec.optionalObject(
            widget['config'],
            'Dashboard widget config',
          );
          ResourceConfigurationCodec.optionalObject(
            widget['size'],
            'Dashboard widget size',
          );
        }
      }
    }
    ResourceConfigurationCodec.objectList(
      config['resourceSlots'],
      'Dashboard resource slots',
    );
    final shared = config['remoteTwitchIds'];
    if (shared != null &&
        (shared is! List || shared.any((id) => id is! String))) {
      throw const FormatException(
        'Shared dashboard IDs must be a list of strings.',
      );
    }
  }
}
