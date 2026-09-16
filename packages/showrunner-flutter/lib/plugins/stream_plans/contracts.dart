import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';

final class StreamPlanNavigationConfig {
  const StreamPlanNavigationConfig({
    this.planId,
    this.segments,
    this.segmentId,
  });

  factory StreamPlanNavigationConfig.fromRuntime(RuntimeMap value) {
    final rawSegments = value['segments'];
    final segments = rawSegments is List
        ? rawSegments
              .whereType<Map>()
              .map((segment) => Map<String, dynamic>.from(segment))
              .toList(growable: false)
        : null;
    return StreamPlanNavigationConfig(
      planId: value['planId']?.toString(),
      segments: segments,
      segmentId: value['segmentId']?.toString(),
    );
  }

  final String? planId;
  final List<RuntimeMap>? segments;
  final String? segmentId;

  RuntimeMap toRuntime() => {
    if (planId != null) 'planId': planId,
    if (segments != null) 'segments': segments,
    if (segmentId != null) 'segmentId': segmentId,
  };
}

final class StreamPlanConfigCodec<C> implements PluginConfigCodec<C> {
  const StreamPlanConfigCodec(this._decoder, this._encoder);

  final C Function(RuntimeMap) _decoder;
  final RuntimeMap Function(C value) _encoder;

  @override
  C decode(RuntimeMap value) => _decoder(value);

  @override
  RuntimeMap encode(C value) => _encoder(value);
}

final streamPlanNavigationConfigCodec = StreamPlanConfigCodec(
  StreamPlanNavigationConfig.fromRuntime,
  (StreamPlanNavigationConfig value) => value.toRuntime(),
);
