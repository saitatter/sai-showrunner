import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';

final class DonorDriveDonationTriggerConfig {
  const DonorDriveDonationTriggerConfig({
    this.minimumAmount,
    this.incentive = false,
  });

  factory DonorDriveDonationTriggerConfig.fromRuntime(RuntimeMap value) =>
      DonorDriveDonationTriggerConfig(
        minimumAmount: _asDouble(value['minimumAmount']),
        incentive: value['incentive'] == true,
      );

  final double? minimumAmount;
  final bool incentive;

  RuntimeMap toRuntime() => {
    if (minimumAmount != null) 'minimumAmount': minimumAmount,
    'incentive': incentive,
  };
}

final class DonorDriveIdTriggerConfig {
  const DonorDriveIdTriggerConfig({this.id});

  factory DonorDriveIdTriggerConfig.fromRuntime(RuntimeMap value) =>
      DonorDriveIdTriggerConfig(id: value['incentive']?.toString());

  final String? id;

  RuntimeMap toRuntime() => {if (id != null) 'incentive': id};

  static DonorDriveIdTriggerConfig milestone(RuntimeMap value) =>
      DonorDriveIdTriggerConfig(id: value['milestone']?.toString());

  RuntimeMap toMilestoneRuntime() => {if (id != null) 'milestone': id};
}

final class DonorDriveConfigCodec<C> implements PluginConfigCodec<C> {
  const DonorDriveConfigCodec(this._decoder, this._encoder);

  final C Function(RuntimeMap) _decoder;
  final RuntimeMap Function(C value) _encoder;

  @override
  C decode(RuntimeMap value) => _decoder(value);

  @override
  RuntimeMap encode(C value) => _encoder(value);
}

final donorDriveDonationTriggerConfigCodec = DonorDriveConfigCodec(
  DonorDriveDonationTriggerConfig.fromRuntime,
  (DonorDriveDonationTriggerConfig value) => value.toRuntime(),
);
final donorDriveIncentiveTriggerConfigCodec = DonorDriveConfigCodec(
  DonorDriveIdTriggerConfig.fromRuntime,
  (DonorDriveIdTriggerConfig value) => value.toRuntime(),
);
final donorDriveMilestoneTriggerConfigCodec = DonorDriveConfigCodec(
  DonorDriveIdTriggerConfig.milestone,
  (DonorDriveIdTriggerConfig value) => value.toMilestoneRuntime(),
);

double? _asDouble(Object? value) => switch (value) {
  num value => value.toDouble(),
  String value => double.tryParse(value),
  _ => null,
};
