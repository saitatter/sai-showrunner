import '../../schema/resource_codec.dart';
import '../../schema/json.dart';

final class OverlayConfigurationCodec extends ResourceConfigurationCodec {
  const OverlayConfigurationCodec();
  @override
  void validate(JsonMap config) {
    super.validate(config);
    final size = ResourceConfigurationCodec.optionalObject(
      config['size'],
      'Overlay size',
    );
    for (final field in ['width', 'height']) {
      final value = size?[field];
      if (value != null && (value is! num || !value.isFinite || value <= 0)) {
        throw const FormatException(
          'Overlay dimensions must be positive finite numbers.',
        );
      }
    }
    for (final widget in ResourceConfigurationCodec.objectList(
      config['widgets'],
      'Overlay widgets',
    )) {
      for (final field in ['position', 'size', 'config']) {
        ResourceConfigurationCodec.optionalObject(
          widget[field],
          'Overlay widget $field',
        );
      }
    }
  }
}
