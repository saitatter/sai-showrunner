/// Bluetooth SIG UUIDs used by the Heart Rate plugin.
abstract final class HeartRateUuids {
  static const heartRateService = '180d';
  static const heartRateMeasurement = '2a37';
  static const bodySensorLocation = '2a38';
  static const heartRateControlPoint = '2a39';
  static const batteryService = '180f';
  static const batteryLevel = '2a19';
  static const deviceInformationService = '180a';

  static String normalize(String uuid) {
    final compact = uuid.trim().toLowerCase().replaceAll('-', '');
    final standardUuid = RegExp(
      r'^0000([0-9a-f]{4})00001000800000805f9b34fb$',
    ).firstMatch(compact);
    return standardUuid?.group(1) ?? compact;
  }
}
