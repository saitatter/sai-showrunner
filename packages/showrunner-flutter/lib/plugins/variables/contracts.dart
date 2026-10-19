import '../../runtime/expression.dart';
import '../../schema/viewer_data.dart';
import '../registry/plugin_contract.dart';

final class VariableNameConfig {
  const VariableNameConfig({required this.variable});

  factory VariableNameConfig.fromRuntime(RuntimeMap value) =>
      VariableNameConfig(variable: value['variable']?.toString() ?? '');

  final String variable;

  RuntimeMap toRuntime() => {'variable': variable};
}

final class VariableValueConfig {
  const VariableValueConfig({required this.variable, this.value});

  factory VariableValueConfig.fromRuntime(RuntimeMap value) =>
      VariableValueConfig(
        variable: value['variable']?.toString() ?? '',
        value: value['value'],
      );

  final String variable;
  final Object? value;

  RuntimeMap toRuntime() => {'variable': variable, 'value': value};
}

final class VariableOffsetConfig {
  const VariableOffsetConfig({
    required this.variable,
    this.offset,
    this.minimum,
    this.maximum,
  });

  factory VariableOffsetConfig.fromRuntime(RuntimeMap value) {
    final clamp = value['clamp'];
    return VariableOffsetConfig(
      variable: value['variable']?.toString() ?? '',
      offset: _asNumber(value['offset']),
      minimum: clamp is Map ? _asNumber(clamp['min']) : null,
      maximum: clamp is Map ? _asNumber(clamp['max']) : null,
    );
  }

  final String variable;
  final num? offset;
  final num? minimum;
  final num? maximum;

  RuntimeMap toRuntime() => {
    'variable': variable,
    'offset': offset,
    if (minimum != null || maximum != null)
      'clamp': {
        if (minimum != null) 'min': minimum,
        if (maximum != null) 'max': maximum,
      },
  };
}

final class ViewerVariableValueConfig {
  const ViewerVariableValueConfig({
    required this.viewer,
    required this.variable,
    this.value,
  });

  factory ViewerVariableValueConfig.fromRuntime(RuntimeMap value) =>
      ViewerVariableValueConfig(
        viewer: ViewerIdentity.fromConfig(value['viewer']),
        variable: value['variable']?.toString() ?? '',
        value: value['value'],
      );

  final ViewerIdentity viewer;
  final String variable;
  final Object? value;

  RuntimeMap toRuntime() => {
    'viewer': viewer.toJson(),
    'variable': variable,
    'value': value,
  };
}

final class ViewerVariableOffsetConfig {
  const ViewerVariableOffsetConfig({
    required this.viewer,
    required this.variable,
    this.offset,
  });

  factory ViewerVariableOffsetConfig.fromRuntime(RuntimeMap value) =>
      ViewerVariableOffsetConfig(
        viewer: ViewerIdentity.fromConfig(value['viewer']),
        variable: value['variable']?.toString() ?? '',
        offset: _asNumber(value['offset']),
      );

  final ViewerIdentity viewer;
  final String variable;
  final num? offset;

  RuntimeMap toRuntime() => {
    'viewer': viewer.toJson(),
    'variable': variable,
    'offset': offset,
  };
}

final class VariableNameConfigCodec
    implements PluginConfigCodec<VariableNameConfig> {
  const VariableNameConfigCodec();

  @override
  VariableNameConfig decode(RuntimeMap value) =>
      VariableNameConfig.fromRuntime(value);

  @override
  RuntimeMap encode(VariableNameConfig value) => value.toRuntime();
}

final class VariableValueConfigCodec
    implements PluginConfigCodec<VariableValueConfig> {
  const VariableValueConfigCodec();

  @override
  VariableValueConfig decode(RuntimeMap value) =>
      VariableValueConfig.fromRuntime(value);

  @override
  RuntimeMap encode(VariableValueConfig value) => value.toRuntime();
}

final class VariableOffsetConfigCodec
    implements PluginConfigCodec<VariableOffsetConfig> {
  const VariableOffsetConfigCodec();

  @override
  VariableOffsetConfig decode(RuntimeMap value) =>
      VariableOffsetConfig.fromRuntime(value);

  @override
  RuntimeMap encode(VariableOffsetConfig value) => value.toRuntime();
}

final class ViewerVariableValueConfigCodec
    implements PluginConfigCodec<ViewerVariableValueConfig> {
  const ViewerVariableValueConfigCodec();

  @override
  ViewerVariableValueConfig decode(RuntimeMap value) =>
      ViewerVariableValueConfig.fromRuntime(value);

  @override
  RuntimeMap encode(ViewerVariableValueConfig value) => value.toRuntime();
}

final class ViewerVariableOffsetConfigCodec
    implements PluginConfigCodec<ViewerVariableOffsetConfig> {
  const ViewerVariableOffsetConfigCodec();

  @override
  ViewerVariableOffsetConfig decode(RuntimeMap value) =>
      ViewerVariableOffsetConfig.fromRuntime(value);

  @override
  RuntimeMap encode(ViewerVariableOffsetConfig value) => value.toRuntime();
}

const variableNameConfigCodec = VariableNameConfigCodec();
const variableValueConfigCodec = VariableValueConfigCodec();
const variableOffsetConfigCodec = VariableOffsetConfigCodec();
const viewerVariableValueConfigCodec = ViewerVariableValueConfigCodec();
const viewerVariableOffsetConfigCodec = ViewerVariableOffsetConfigCodec();

num? _asNumber(Object? value) => value is num ? value : null;
