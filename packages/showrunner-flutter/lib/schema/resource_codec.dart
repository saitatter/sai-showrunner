import 'json.dart';
import 'resource.dart';

/// A provider owns its configuration validation; no normalization or migration.
class ResourceConfigurationCodec {
  const ResourceConfigurationCodec();

  /// Shipped resource configurations have no independent version envelope.
  int? get version => null;
  void validate(JsonMap config) {
    if (config['name'] != null && config['name'] is! String) {
      throw const FormatException('Resource name must be text.');
    }
  }

  static Map? optionalObject(Object? value, String field) {
    if (value == null) return null;
    if (value is! Map) throw FormatException('$field must be an object.');
    return value;
  }

  static Iterable<Map> objectList(Object? value, String field) {
    if (value == null) return const [];
    if (value is! List || value.any((item) => item is! Map)) {
      throw FormatException('$field must be a list of objects.');
    }
    return value.cast<Map>();
  }
}

final class ResourceDataCodec {
  const ResourceDataCodec([
    this.configuration = const ResourceConfigurationCodec(),
  ]);
  final ResourceConfigurationCodec configuration;
  ResourceData decode(JsonMap json) {
    final resource = ResourceData.fromJson(json);
    configuration.validate(resource.config);
    return resource;
  }

  JsonMap encode(ResourceData resource) {
    configuration.validate(resource.config);
    return resource.toJson();
  }
}
