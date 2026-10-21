import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

/// Opt-in allocation samples for the canonical payload's map/list/string classes.
/// Tracing is enabled only for untimed probes; this is not retained heap size.
final class BenchmarkAllocations {
  BenchmarkAllocations._(this._base, this._isolate);
  final Uri _base;
  final String _isolate;
  final HttpClient _client = HttpClient();
  final List<String> _classes = [];

  static Future<BenchmarkAllocations?> connect() async {
    if (Platform.environment['SHOWRUNNER_BENCH_ALLOCATIONS'] != '1') {
      return null;
    }
    final info = await developer.Service.getInfo();
    final uri = info.serverUri;
    final isolate = developer.Service.getIsolateId(Isolate.current);
    if (uri == null || isolate == null) {
      throw StateError(
        'Allocation probe requires --enable-vmservice --concurrency=1.',
      );
    }
    return BenchmarkAllocations._(uri, isolate);
  }

  Future<Map> _rpc(String method, Map<String, String> arguments) async {
    final uri = _base
        .resolve(method)
        .replace(queryParameters: {'isolateId': _isolate, ...arguments});
    final response = await (await _client.getUrl(uri)).close();
    final json = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
    if (json['error'] != null) {
      throw StateError('Allocation probe RPC $method failed.');
    }
    return json['result'] as Map;
  }

  Future<void> _enable() async {
    if (_classes.isNotEmpty) return;
    final list = await _rpc('getClassList', {});
    for (final entry in list['classes'] as List) {
      if (const {
        '_Map',
        '_List',
        '_GrowableList',
        '_OneByteString',
        '_TwoByteString',
      }.contains(entry['name'])) {
        final id = entry['id'] as String;
        await _rpc('setTraceClassAllocation', {
          'classId': id,
          'enable': 'true',
        });
        _classes.add(id);
      }
    }
    if (_classes.isEmpty) {
      throw StateError('Allocation probe found no target classes.');
    }
  }

  Future<int> measure(void Function() operation) async {
    await _enable();
    final start = developer.Timeline.now;
    operation();
    final elapsed = developer.Timeline.now - start;
    final traces = await _rpc('getAllocationTraces', {
      'timeOriginMicros': '$start',
      'timeExtentMicros': '$elapsed',
    });
    return (traces['samples'] as List).length;
  }

  Future<void> close() async {
    try {
      for (final id in _classes) {
        await _rpc('setTraceClassAllocation', {
          'classId': id,
          'enable': 'false',
        });
      }
    } finally {
      _client.close(force: true);
    }
  }
}
